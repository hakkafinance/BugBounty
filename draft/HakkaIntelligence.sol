pragma solidity 0.5.17;

library SafeMath {

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) 
            return 0;
        uint256 c = a * b;
        require(c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0);
        uint256 c = a / b;
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a);
        uint256 c = a - b;
        return c;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a);
        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0);
        return a % b;
    }

    function sqrt(uint256 x) internal pure returns (uint256) {
        uint256 z = add(x >> 1, 1);
        uint256 y = x;
        while (z < y)
        {
            y = z;
            z = ((add((x / z), z)) / 2);
        }
        return y;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint);
    function balanceOf(address account) external view returns (uint);
    function transfer(address recipient, uint amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint);
    function approve(address spender, uint amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
}

contract Oracle {
    function latestAnswer() external view returns (int256);
}

contract HakkaIntelligence {
    using SafeMath for *;

    IERC20 public token;

    uint256 public totalStake;
    uint256 public revealedStake;
    uint256 public totalScore;
    uint256 public offset;

    // timeline
    //                          poke                     poke
    // deploy contract ---- period start ---- period stop-|-reveal open --- reveal close～～～
    //        \----- can bet -----/                        \---- must reveal----/  \---can claim--

    uint256 public periodStart;
    uint256 public periodStop;
    uint256 public revealOpen;
    uint256 public revealClose;

    uint256 public elementCount;
    address[] public oracles;
    uint256[] public priceSnapshot;
    uint256[] public answer;

    struct Player {
        bool revealed;
        bool claimed;
        uint256 stake;
        uint256 score;
        uint256[] submission;
    }

    mapping(address => Player) public players;

    event Submit(address indexed player, uint256[] submission);
    event Reveal(address indexed player, uint256 score);
    event Claim(address indexed player, uint256 amount);

    constructor(address[] memory _oracles, address _token, uint256 _periodStart, uint256 _periodStop) public {
        oracles = _oracles;
        elementCount = _oracles.length;
        token = IERC20(_token);
        periodStart = _periodStart;
        periodStop = _periodStop;
    }

    function calcLength(uint256[] memory vector) public pure returns (uint256 l) {
        for(uint256 i = 0; i < vector.length; i++)
            l = l.add(vector[i].mul(vector[i]));
        l = l.sqrt();
    }

    function innerProduct(uint256[] memory vector1, uint256[] memory vector2) public pure returns (uint256 xy) {
        require(vector1.length == vector2.length);
        for(uint256 i = 0; i < vector1.length; i++)
            xy = xy.add(vector1[i].mul(vector2[i]));
    }

    function submit(uint256 stake, uint256[] memory submission) public {
        Player storage player = players[msg.sender];

        require(now <= periodStart);
        require(submission.length == elementCount);
        require(player.submission.length == 0);
        require(calcLength(submission) <= 1e18);

        totalStake = totalStake.add(stake);
        player.stake = stake;

        player.submission = submission;
        require(token.transferFrom(msg.sender, address(this), stake));
        emit Submit(msg.sender, submission);
    }

    function reveal(address _player) public returns (uint256 score) {
        Player storage player = players[_player];

        require(!player.revealed);
        require(now >= revealOpen && now <= revealClose);

        score = innerProduct(answer, player.submission).mul(player.stake);
        revealedStake = revealedStake.add(player.stake);
        player.revealed = true;
        player.score = score;
        totalScore = totalScore.add(score);

        emit Reveal(_player, score);
    }

    function claim(address _player) public returns (uint256 amount) {
        Player storage player = players[_player];

        require(now > revealClose);
        require(!player.claimed);
        player.claimed = true;
        amount = token.balanceOf(address(this)).mul(player.score).div(totalScore.sub(offset));
        offset = offset.add(player.score);
        require(token.transfer(_player, amount));

        emit Claim(_player, amount);
    }

    function proceed() public {
        if(priceSnapshot.length == 0) {
            require(now >= periodStart);
            for(uint256 i = 0; i < elementCount; i++) {
                priceSnapshot.push(uint256(Oracle(oracles[i]).latestAnswer()));
            }
        }
        else if(answer.length == 0) {
            require(now >= periodStop);
            uint256[] memory _answer = new uint256[](elementCount);
            for(uint256 i = 0; i < elementCount; i++)
                _answer[i] = uint256(Oracle(oracles[i]).latestAnswer()).mul(1e18).div(priceSnapshot[i]);
            uint256 _length = calcLength(_answer).add(1);
            for(uint256 i = 0; i < elementCount; i++)
                _answer[i] = _answer[i].mul(1e18).div(_length);
            answer = _answer;
            revealOpen = now;
            revealClose = now.add(14 days);
        }
        else revert();
    }

}
