pragma solidity 0.6.1;

import "../dependencies/DSMath.sol";
import "../dependencies/token/BurnableToken.sol";
import "../prices/IPriceSource.sol";
import "../fund/participation/IParticipation.sol";
import "../fund/trading/Trading.sol";
import "../version/Registry.sol";

/// @notice Liquidity contract and token sink
contract Engine is DSMath {
    event RegistryChange(address registry);
    event SetAmguPrice(uint256 amguPrice);
    event AmguConsumed(
        uint256 amguPaid,
        uint256 etherPaid,
        uint256 totalAmguConsumed,
        uint256 totalEtherConsumed
    );
    event Thaw(uint256 amount);
    event Burn(uint256 amount);
    event IncentivePaid(
        address indexed participationContract,
        address indexed requestOwner,
        uint256 incentiveAmount
    );

    uint8 public constant MLN_DECIMALS = 18;

    Registry public registry;
    uint256 public amguPrice;
    uint256 public frozenEther;
    uint256 public liquidEther;
    uint256 public lastThaw;
    uint256 public thawingDelay;
    uint256 public totalEtherConsumed;
    uint256 public totalAmguConsumed;
    uint256 public totalMlnBurned;

    constructor(uint256 _delay, address _registry) public {
        lastThaw = block.timestamp;
        thawingDelay = _delay;
        __setRegistry(_registry);
    }

    modifier onlyFund() {
        require(
            registry.isFund(msg.sender),
            "Only funds can call this"
        );
        _;
    }

    modifier onlyMGM() {
        require(
            msg.sender == registry.MGM(),
            "Only MGM can call this"
        );
        _;
    }

    /// @dev Registry owner is MTC
    modifier onlyMTC() {
        require(
            msg.sender == registry.owner(),
            "Only MTC can call this"
        );
        _;
    }

    function __setRegistry(address _registry) internal {
        registry = Registry(_registry);
        emit RegistryChange(address(registry));
    }

    /// @dev only callable by MTC
    function setRegistry(address _registry)
        external
        onlyMTC
    {
        __setRegistry(_registry);
    }

    /// @dev set price of AMGU in MLN (base units)
    /// @dev only callable by MGM
    function setAmguPrice(uint256 _price)
        external
        onlyMGM
    {
        amguPrice = _price;
        emit SetAmguPrice(_price);
    }

    function getAmguPrice() public view returns (uint256) { return amguPrice; }

    function premiumPercent() public view returns (uint256) {
        if (liquidEther < 1 ether) {
            return 0;
        } else if (liquidEther >= 1 ether && liquidEther < 5 ether) {
            return 5;
        } else if (liquidEther >= 5 ether && liquidEther < 10 ether) {
            return 10;
        } else if (liquidEther >= 10 ether) {
            return 15;
        }
    }

    /// @dev not adding to liquidEther, since it is immediately sent away again
    function receiveIncentiveInEth() external payable {}

    function payAmguInEther() external payable {
        require(
            registry.isFundFactory(msg.sender) ||
            registry.isFund(msg.sender),
            "Sender must be a fund or the factory"
        );
        uint256 mlnPerAmgu = getAmguPrice();
        uint256 ethPerMln;
        (ethPerMln,) = priceSource().getPrice(address(mlnToken()));
        uint256 amguConsumed;
        if (mlnPerAmgu > 0 && ethPerMln > 0) {
            amguConsumed = (mul(msg.value, 10 ** uint256(MLN_DECIMALS))) / (mul(ethPerMln, mlnPerAmgu));
        } else {
            amguConsumed = 0;
        }
        totalEtherConsumed = add(totalEtherConsumed, msg.value);
        totalAmguConsumed = add(totalAmguConsumed, amguConsumed);
        frozenEther = add(frozenEther, msg.value);
        emit AmguPaid(
            amguConsumed,
            msg.value,
            totalAmguConsumed,
            totalEtherConsumed
        );
    }

    /// @notice Move frozen ether to liquid pool after delay
    /// @dev Delay only restarts when this function is called
    function thaw() external {
        require(
            block.timestamp >= add(lastThaw, thawingDelay),
            "Thawing delay has not passed"
        );
        require(frozenEther > 0, "No frozen ether to thaw");
        lastThaw = block.timestamp;
        liquidEther = add(liquidEther, frozenEther);
        emit Thaw(frozenEther);
        frozenEther = 0;
    }

    /// @return ETH per MLN with some percent _premium
    function getEthPerMlnWithPremium(uint256 _premium) public view returns (uint256) {
        uint256 ethPerMln;
        (ethPerMln,) = priceSource().getPrice(address(mlnToken()));
        uint256 premium = (mul(ethPerMln, _premium) / 100);
        return add(ethPerMln, premium);
    }

    /// @return ETH per MLN including standard engine premium
    function enginePrice() public view returns (uint256) {
        return getEthPerMlnWithPremium(premiumPercent());
    }

    /// @return Amount of liquid ETH to give for some _mlnAmount
    function ethPayoutForMlnAmount(uint256 _mlnAmount) public view returns (uint256) {
        return mul(_mlnAmount, enginePrice()) / 10 ** uint256(MLN_DECIMALS);
    }

    /// @return Amount of MLN needed to receive some _incentive amount of ETH
    function mlnRequiredForIncentiveAmount(uint256 _incentive) public view returns (uint256) {
        return mul(_incentive, 1 ether) / getEthPerMlnWithPremium(20);
    }

    /// @dev MLN must be approved first
    function sellAndBurnMln(uint256 _mlnAmount)
        external
        onlyFund
    {
        require(
            mlnToken().transferFrom(msg.sender, address(this), _mlnAmount),
            "sellAndBurnMln: MLN transferFrom failed"
        );
        uint256 ethToSend = ethPayoutForMlnAmount(_mlnAmount);
        require(ethToSend > 0, "sellAndBurnMln: No ether to pay out");
        require(liquidEther >= ethToSend, "sellAndBurnMln: Not enough liquid ether to send");
        liquidEther = sub(liquidEther, ethToSend);
        totalMlnBurned = add(totalMlnBurned, _mlnAmount);
        msg.sender.transfer(ethToSend);
        mlnToken().burn(_mlnAmount);
        emit Burn(_mlnAmount);
    }

    /// @dev MLN must be approved by msg.sender first
    function executeRequestAndBurnMln(address _participation, address _requestOwner) external {
        uint256 incentiveAmount = IParticipation(_participation).getRequestIncentive(_requestOwner);
        uint256 mlnAmount = mlnRequiredForIncentiveAmount(incentiveAmount);
        require(
            mlnToken().balanceOf(msg.sender) >= mlnAmount,
            "executeRequestAndBurnMln: Sender does not have enough MLN"
        );
        require(
            mlnToken().transferFrom(msg.sender, address(this), mlnAmount),
            "executeRequestAndBurnMln: MLN transferFrom failed"
        );
        mlnToken().burn(mlnAmount);
        IParticipation(_participation).executeRequestFor(_requestOwner);
        require(
            msg.sender.send(incentiveAmount),
            "executeRequestAndBurnMln: Incentive transfer failed"
        );
        emit IncentivePaid(_participation, _requestOwner, incentiveAmount);
        emit Burn(mlnAmount);
    }

    /// @dev Get MLN from the registry
    function mlnToken()
        public
        view
        returns (BurnableToken)
    {
        return BurnableToken(registry.mlnToken());
    }

    /// @dev Get PriceSource from the registry
    function priceSource()
        public
        view
        returns (IPriceSource)
    {
        return IPriceSource(registry.priceSource());
    }
}
