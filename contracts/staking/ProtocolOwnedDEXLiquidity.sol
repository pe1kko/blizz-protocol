pragma solidity 0.7.6;

import "../dependencies/openzeppelin/contracts/SafeMath.sol";
import "../dependencies/openzeppelin/contracts/IERC20.sol";
import "../dependencies/openzeppelin/contracts/Ownable.sol";
import "../interfaces/IChefIncentivesController.sol";

interface IJoePair {
    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);
}

interface IMultiFeeDistribution {
    function lockedBalances(address user) view external returns (uint256);
    function lockedSupply() external view returns (uint256);
}

contract ProtocolOwnedDEXLiquidity is Ownable {

    using SafeMath for uint256;

    IJoePair constant public lpToken = IJoePair(0xac3F978714c613E768272c502a8912bC03DCf624);
    IERC20 constant public bAVAX = IERC20(0xB2AC04b71888E17Aa2c5102cf3d0215467D74100);
    IMultiFeeDistribution constant public treasury = IMultiFeeDistribution(0xA867c1acA4B5F1E0a66cf7b1FE33525D57608854);
    address constant public burn = 0x8d426bfe128b171D8FD38a58dFeA257F01206F34;

    struct UserRecord {
        uint256 nextClaimTime;
        uint256 claimCount;
        uint256 totalBoughtAVAX;
    }

    mapping (address => UserRecord) public userData;

    uint public totalSoldAVAX;
    uint public minBuyAmount;
    uint public minSuperPODLLock;
    uint public buyCooldown;
    uint public superPODLCooldown;
    uint public lockedBalanceMultiplier;

    event SoldAVAX(
        address indexed buyer,
        uint256 amount
    );
    event AaaaaaahAndImSuperPODLiiiiing(
        address indexed podler,
        uint256 amount
    );

    constructor(
        uint256 _lockMultiplier,
        uint256 _minBuy,
        uint256 _minLock,
        uint256 _cooldown,
        uint256 _podlCooldown
    ) Ownable() {
        IChefIncentivesController chef = IChefIncentivesController(0x2d867AE30400ffFaD9BeD8472c514c2d6b827F5f);
        chef.setClaimReceiver(address(this), address(treasury));
        setParams(_lockMultiplier, _minBuy, _minLock, _cooldown, _podlCooldown);
    }

    function setParams(
        uint256 _lockMultiplier,
        uint256 _minBuy,
        uint256 _minLock,
        uint256 _cooldown,
        uint256 _podlCooldown
    ) public onlyOwner {
        require(_minBuy >= 1e18);
        lockedBalanceMultiplier = _lockMultiplier;
        minBuyAmount = _minBuy;
        minSuperPODLLock = _minLock;
        buyCooldown = _cooldown;
        superPODLCooldown = _podlCooldown;
    }

    function protocolOwnedReserves() public view returns (uint256 blizz, uint256 wavax) {
        (uint reserve0, uint reserve1,) = lpToken.getReserves();
        uint balance = lpToken.balanceOf(burn);
        uint totalSupply = lpToken.totalSupply();
        return (reserve0.mul(balance).div(totalSupply), reserve1.mul(balance).div(totalSupply));
    }

    function availableAVAX() public view returns (uint256) {
        return bAVAX.balanceOf(address(this)) / 2;
    }

    function availableForUser(address _user) public view returns (uint256) {
        UserRecord storage u = userData[_user];
        if (u.nextClaimTime > block.timestamp) return 0;
        uint available = availableAVAX();
        uint userLocked = treasury.lockedBalances(_user);
        uint totalLocked = treasury.lockedSupply();
        uint amount = available.mul(lockedBalanceMultiplier).mul(userLocked).div(totalLocked);
        if (amount > available) {
            return available;
        }
        return amount;
    }

    function lpTokensPerOneAVAX() public view returns (uint256) {
        uint totalSupply = lpToken.totalSupply();
        (,uint reserve1,) = lpToken.getReserves();
        return totalSupply.mul(1e18).mul(45).div(reserve1).div(100);
    }

    function _buy(uint _amount, uint _cooldownTime) internal {
        UserRecord storage u = userData[msg.sender];

        require(_amount >= minBuyAmount, "Below min buy amount");
        require(block.timestamp >= u.nextClaimTime, "Claimed too recently");

        uint lpAmount = _amount.mul(lpTokensPerOneAVAX()).div(1e18);
        lpToken.transferFrom(msg.sender, burn, lpAmount);
        bAVAX.transfer(msg.sender, _amount);
        bAVAX.transfer(address(treasury), _amount);

        u.nextClaimTime = block.timestamp.add(_cooldownTime);
        u.claimCount = u.claimCount.add(1);
        u.totalBoughtAVAX = u.totalBoughtAVAX.add(_amount);
        totalSoldAVAX = totalSoldAVAX.add(_amount);

        emit SoldAVAX(msg.sender, _amount);
    }

    function buyAVAX(uint256 _amount) public {
        require(_amount <= availableForUser(msg.sender), "Amount exceeds user limit");
        _buy(_amount, buyCooldown);
    }

    function superPODL(uint256 _amount) public {
        require(treasury.lockedBalances(msg.sender) >= minSuperPODLLock, "Need to lock BLZZ!");
        _buy(_amount, superPODLCooldown);
        emit AaaaaaahAndImSuperPODLiiiiing(msg.sender, _amount);
    }
}
