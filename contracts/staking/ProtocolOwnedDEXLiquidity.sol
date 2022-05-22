pragma solidity 0.7.6;

import "../dependencies/openzeppelin/contracts/SafeMath.sol";
import "../dependencies/openzeppelin/contracts/SafeERC20.sol";
import "../dependencies/openzeppelin/contracts/IERC20.sol";
import "../dependencies/openzeppelin/contracts/Ownable.sol";
import "../interfaces/IChefIncentivesController.sol";

interface IPancakeLPToken is IERC20 {
    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );
}

interface IMultiFeeDistribution {
    function lockedBalances(address user) view external returns (uint256);
    function lockedSupply() external view returns (uint256);
}

contract ProtocolOwnedDEXLiquidity is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IPancakeLPToken;

    IPancakeLPToken constant public lpToken = IPancakeLPToken(0x829F540957DFC652c4466a7F34de611E172e64E8);
    IERC20 constant public vWBNB = IERC20(0xB11A912CD93DcffA8b609b4C021E89723ceb7FE8);
    IMultiFeeDistribution constant public treasury = IMultiFeeDistribution(0x685D3b02b9b0F044A3C01Dbb95408FC2eB15a3b3);

    struct UserRecord {
        uint256 nextClaimTime;
        uint256 claimCount;
        uint256 totalBoughtBNB;
    }

    mapping (address => UserRecord) public userData;

    uint public totalSoldBNB;
    uint public minBuyAmount;
    uint public minSuperPODLLock;
    uint public buyCooldown;
    uint public superPODLCooldown;
    uint public lockedBalanceMultiplier;

    event ParamsSet(
        uint256 lockMultiplier,
        uint256 minBuy,
        uint256 minLock,
        uint256 cooldown,
        uint256 podlCooldown
    );
    event SoldBNB(
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
        IChefIncentivesController chef = IChefIncentivesController(0xB7c1d99069a4eb582Fc04E7e1124794000e7ecBF);
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
        emit ParamsSet(_lockMultiplier, _minBuy, _minLock, _cooldown, _podlCooldown);
    }

    function protocolOwnedReserves() public view returns (uint256 wbnb, uint256 valas) {
        (uint reserve0, uint reserve1,) = lpToken.getReserves();
        uint balance = lpToken.balanceOf(address(this));
        uint totalSupply = lpToken.totalSupply();
        return (reserve1.mul(balance).div(totalSupply), reserve0.mul(balance).div(totalSupply));
    }

    function availableBNB() public view returns (uint256) {
        return vWBNB.balanceOf(address(this)) / 2;
    }

    function availableForUser(address _user) public view returns (uint256) {
        UserRecord storage u = userData[_user];
        if (u.nextClaimTime > block.timestamp) return 0;
        uint available = availableBNB();
        uint userLocked = treasury.lockedBalances(_user);
        uint totalLocked = treasury.lockedSupply();
        uint amount = available.mul(lockedBalanceMultiplier).mul(userLocked).div(totalLocked);
        if (amount > available) {
            return available;
        }
        return amount;
    }

    function lpTokensPerOneBNB() public view returns (uint256) {
        uint totalSupply = lpToken.totalSupply();
        (,uint reserve1,) = lpToken.getReserves();
        return totalSupply.mul(1e18).mul(45).div(reserve1).div(100);
    }

    function _buy(uint _amount, uint _cooldownTime) internal {
        UserRecord storage u = userData[msg.sender];

        require(_amount >= minBuyAmount, "Below min buy amount");
        require(block.timestamp >= u.nextClaimTime, "Claimed too recently");

        uint lpAmount = _amount.mul(lpTokensPerOneBNB()).div(1e18);
        lpToken.safeTransferFrom(msg.sender, address(this), lpAmount);
        vWBNB.safeTransfer(msg.sender, _amount);
        vWBNB.safeTransfer(address(treasury), _amount);

        u.nextClaimTime = block.timestamp.add(_cooldownTime);
        u.claimCount = u.claimCount.add(1);
        u.totalBoughtBNB = u.totalBoughtBNB.add(_amount);
        totalSoldBNB = totalSoldBNB.add(_amount);

        emit SoldBNB(msg.sender, _amount);
    }

    function buyBNB(uint256 _amount) public {
        require(_amount <= availableForUser(msg.sender), "Amount exceeds user limit");
        _buy(_amount, buyCooldown);
    }

    function superPODL(uint256 _amount) public {
        require(treasury.lockedBalances(msg.sender) >= minSuperPODLLock, "Need to lock VALAS!");
        _buy(_amount, superPODLCooldown);
        emit AaaaaaahAndImSuperPODLiiiiing(msg.sender, _amount);
    }
}
