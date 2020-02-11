pragma solidity 0.6.1;
pragma experimental ABIEncoderV2;

import "../hub/Spoke.sol";
import "../vault/Vault.sol";
import "../policies/PolicyManager.sol";
import "../policies/TradingSignatures.sol";
import "../../factory/Factory.sol";
import "../../dependencies/DSMath.sol";
import "../../exchanges/ExchangeAdapter.sol";
import "../../exchanges/interfaces/IZeroExV2.sol";
import "../../exchanges/interfaces/IZeroExV3.sol";
import "../../version/Registry.sol";
import "../../dependencies/TokenUser.sol";

contract Trading is DSMath, TokenUser, Spoke, TradingSignatures {
    event ExchangeMethodCall(
        address indexed exchangeAddress,
        string indexed methodSignature,
        address[8] orderAddresses,
        uint[8] orderValues,
        bytes[4] orderData,
        bytes32 identifier,
        bytes signature
    );

    struct Exchange {
        address exchange;
        address adapter;
        bool takesCustody;
    }

    enum UpdateType { make, take, cancel }

    struct Order {
        address exchangeAddress;
        bytes32 orderId;
        UpdateType updateType;
        address makerAsset;
        address takerAsset;
        uint makerQuantity;
        uint takerQuantity;
        uint timestamp;
        uint fillTakerQuantity;
    }

    struct OpenMakeOrder {
        uint id; // Order Id from exchange
        uint expiresAt; // Timestamp when the order expires
        uint orderIndex; // Index of the order in the orders array
        address buyAsset; // Address of the buy asset in the order
    }

    Exchange[] public exchanges;
    Order[] public orders;
    mapping (address => bool) public adapterIsAdded;
    mapping (address => mapping(address => OpenMakeOrder)) public exchangesToOpenMakeOrders;
    mapping (address => uint) public openMakeOrdersAgainstAsset;
    mapping (address => bool) public isInOpenMakeOrder;
    mapping (address => uint) public makerAssetCooldown;
    mapping (bytes32 => IZeroExV2.Order) internal orderIdToZeroExV2Order;
    mapping (bytes32 => IZeroExV3.Order) internal orderIdToZeroExV3Order;

    uint public constant ORDER_LIFESPAN = 1 days;
    uint public constant MAKE_ORDER_COOLDOWN = 30 minutes;

    modifier delegateInternal() {
        require(msg.sender == address(this), "Sender is not this contract");
        _;
    }

    constructor(
        address _hub,
        address[] memory _exchanges,
        address[] memory _adapters,
        address _registry
    )
        public
        Spoke(_hub)
    {
        routes.registry = _registry;
        require(_exchanges.length == _adapters.length, "Array lengths unequal");
        for (uint i = 0; i < _exchanges.length; i++) {
            _addExchange(_exchanges[i], _adapters[i]);
        }
    }

    /// @notice Receive ether function (used to receive ETH from WETH)
    receive() external payable {}

    function addExchange(address _exchange, address _adapter) external auth {
        _addExchange(_exchange, _adapter);
    }

    function _addExchange(
        address _exchange,
        address _adapter
    ) internal {
        require(!adapterIsAdded[_adapter], "Adapter already added");
        adapterIsAdded[_adapter] = true;
        Registry registry = Registry(routes.registry);
        require(
            registry.exchangeAdapterIsRegistered(_adapter),
            "Adapter is not registered"
        );

        address registeredExchange;
        bool takesCustody;
        (registeredExchange, takesCustody) = registry.getExchangeInformation(_adapter);

        require(
            registeredExchange == _exchange,
            "Exchange and adapter do not match"
        );
        exchanges.push(Exchange(_exchange, _adapter, takesCustody));
    }

    // /// @notice Universal method for calling exchange functions through adapters
    // /// @notice See adapter contracts for parameters needed for each exchange
    // /// @param exchangeIndex Index of the exchange in the "exchanges" array
    // /// @param orderAddresses [0] Order maker
    // /// @param orderAddresses [1] Order taker
    // /// @param orderAddresses [2] Order maker asset
    // /// @param orderAddresses [3] Order taker asset
    // /// @param orderAddresses [4] feeRecipientAddress
    // /// @param orderAddresses [5] senderAddress
    // /// @param orderAddresses [6] maker fee asset
    // /// @param orderAddresses [7] taker fee asset
    // /// @param orderValues [0] makerAssetAmount
    // /// @param orderValues [1] takerAssetAmount
    // /// @param orderValues [2] Maker fee
    // /// @param orderValues [3] Taker fee
    // /// @param orderValues [4] expirationTimeSeconds
    // /// @param orderValues [5] Salt/nonce
    // /// @param orderValues [6] Fill amount: amount of taker token to be traded
    // /// @param orderValues [7] Dexy signature mode
    // /// @param orderData [0] Encoded data specific to maker asset
    // /// @param orderData [1] Encoded data specific to taker asset
    // /// @param orderData [2] Encoded data specific to maker asset fee
    // /// @param orderData [3] Encoded data specific to taker asset fee
    // /// @param identifier Order identifier
    // /// @param signature Signature of order maker
    function callOnExchange(
        uint exchangeIndex,
        string memory methodSignature,
        // address[8] memory orderAddresses,
        // uint[8] memory orderValues,
        // bytes[4] memory orderData,
        bytes32 identifier,
        // bytes memory signature
        bytes memory _encodedParametersForExchange
    )
        public
        onlyInitialized
    {
        bytes4 methodSelector = bytes4(keccak256(bytes(methodSignature)));
        require(
            Registry(routes.registry).adapterMethodIsAllowed(
                exchanges[exchangeIndex].adapter,
                methodSelector
            ),
            "Adapter method not allowed"
        );
        (address[6] memory addrsForValidations, uint[3] memory valsForValidations) = _getParametersForRiskManagement(exchangeIndex, _encodedParametersForExchange);
        PolicyManager(routes.policyManager).preValidate(methodSelector, [addrsForValidations[0], addrsForValidations[1], addrsForValidations[2], addrsForValidations[3], exchanges[exchangeIndex].exchange], [valsForValidations[0], valsForValidations[1], valsForValidations[2]], identifier);
        if (
            methodSelector == MAKE_ORDER ||
            methodSelector == TAKE_ORDER ||
            methodSelector == TEST_TAKE_ORDER
        ) {
            require(Registry(routes.registry).assetIsRegistered(
                addrsForValidations[2]), 'Maker asset not registered'
            );
            require(Registry(routes.registry).assetIsRegistered(
                addrsForValidations[3]), 'Taker asset not registered'
            );
            if (addrsForValidations[4] != address(0) && methodSelector == MAKE_ORDER) {
                require(
                    Registry(routes.registry).assetIsRegistered(addrsForValidations[4]),
                    'Maker fee asset not registered'
                );
            }
            if (addrsForValidations[5] != address(0) && methodSelector == TAKE_ORDER) {
                require(
                    Registry(routes.registry).assetIsRegistered(addrsForValidations[5]),
                    'Taker fee asset not registered'
                );
            }
            if (addrsForValidations[5] != address(0) && methodSelector == TEST_TAKE_ORDER) {
                require(
                    Registry(routes.registry).assetIsRegistered(addrsForValidations[5]),
                    'Taker fee asset not registered'
                );
            }
        }
        (bool success, bytes memory returnData) = exchanges[exchangeIndex].adapter.delegatecall(
            abi.encodeWithSignature(
                methodSignature,
                // exchanges[exchangeIndex].exchange,
                // orderAddresses,
                // orderValues,
                // orderData,
                // identifier,
                // signature,
                _encodedParametersForExchange
            )
        );
        require(success, string(returnData));
        PolicyManager(routes.policyManager).postValidate(methodSelector, [addrsForValidations[0], addrsForValidations[1], addrsForValidations[2], addrsForValidations[3], exchanges[exchangeIndex].exchange], [valsForValidations[0], valsForValidations[1], valsForValidations[2]], identifier);
        // emit ExchangeMethodCall(
            // exchanges[exchangeIndex].exchange,
            // methodSignature,
            // orderAddresses,
            // orderValues,
            // orderData,
            // identifier,
            // signature
        // );
    }

    function getAssetAddress(bytes memory assetData)
        internal
        view
        returns (address assetAddress)
    {
        assembly {
            assetAddress := mload(add(assetData, 36))
        }
    }

    // address makerAddress,
    // address takerAddress,
    // address makerAsset,
    // address takerAsset,
    // address makerFeeAsset,
    // address takerFeeAsset,
    // uint makerAssetAmount,
    // uint takerAssetAmount,
    // uint fillAmout
    function _getParametersForRiskManagement(
        uint exchangeIndex,
        bytes memory encodedParameters
    )
        internal
        returns (address[6] memory, uint[3] memory)
    {
        address[6] memory addrs;
        uint[3] memory vals;

        if (ExchangeAdapter(exchanges[exchangeIndex].adapter).decoderId() == 0) { // 0xV2
            (
                address[5] memory orderAddresses,
                uint[7] memory orderValues,
                bytes[3] memory orderData
            ) = abi.decode(encodedParameters, (address[5], uint[7], bytes[3]));

            addrs = [
                orderAddresses[0],
                orderAddresses[1],
                getAssetAddress(orderData[0]),
                getAssetAddress(orderData[1]),
                address(0),
                address(0)
            ];

            vals = [
                orderValues[0],
                orderValues[1],
                orderValues[6]
            ];
        }
        return (addrs, vals);
    }

    /// @dev Make sure this is called after orderUpdateHook in adapters
    function addOpenMakeOrder(
        address ofExchange,
        address sellAsset,
        address buyAsset,
        uint orderId,
        uint expirationTime
    ) public delegateInternal {
        require(!isInOpenMakeOrder[sellAsset], "Asset already in open order");
        require(orders.length > 0, "No orders in array");

        // If expirationTime is 0, actualExpirationTime is set to ORDER_LIFESPAN from now
        uint actualExpirationTime = (expirationTime == 0) ? add(block.timestamp, ORDER_LIFESPAN) : expirationTime;

        require(
            actualExpirationTime <= add(block.timestamp, ORDER_LIFESPAN) &&
            actualExpirationTime > block.timestamp,
            "Expiry time greater than max order lifespan or has already passed"
        );
        isInOpenMakeOrder[sellAsset] = true;
        makerAssetCooldown[sellAsset] = add(actualExpirationTime, MAKE_ORDER_COOLDOWN);
        openMakeOrdersAgainstAsset[buyAsset] = add(openMakeOrdersAgainstAsset[buyAsset], 1);
        exchangesToOpenMakeOrders[ofExchange][sellAsset].id = orderId;
        exchangesToOpenMakeOrders[ofExchange][sellAsset].expiresAt = actualExpirationTime;
        exchangesToOpenMakeOrders[ofExchange][sellAsset].orderIndex = sub(orders.length, 1);
        exchangesToOpenMakeOrders[ofExchange][sellAsset].buyAsset = buyAsset;

    }

    function _removeOpenMakeOrder(
        address exchange,
        address sellAsset
    ) internal {
        if (isInOpenMakeOrder[sellAsset]) {

            makerAssetCooldown[sellAsset] = add(block.timestamp, MAKE_ORDER_COOLDOWN);
            address buyAsset = exchangesToOpenMakeOrders[exchange][sellAsset].buyAsset;
            delete exchangesToOpenMakeOrders[exchange][sellAsset];
            openMakeOrdersAgainstAsset[buyAsset] = sub(openMakeOrdersAgainstAsset[buyAsset], 1);
        }
    }

    function removeOpenMakeOrder(
        address exchange,
        address sellAsset
    ) public delegateInternal {
        _removeOpenMakeOrder(exchange, sellAsset);
    }

    /// @dev Bit of Redundancy for now
    function addZeroExV2OrderData(
        bytes32 orderId,
        IZeroExV2.Order memory zeroExOrderData
    ) public delegateInternal {
        orderIdToZeroExV2Order[orderId] = zeroExOrderData;
    }
    function addZeroExV3OrderData(
        bytes32 orderId,
        IZeroExV3.Order memory zeroExOrderData
    ) public delegateInternal {
        orderIdToZeroExV3Order[orderId] = zeroExOrderData;
    }

    function orderUpdateHook(
        address ofExchange,
        bytes32 orderId,
        UpdateType updateType,
        address payable[2] memory orderAddresses,
        uint[3] memory orderValues
    ) public delegateInternal {
        // only save make/take
        if (updateType == UpdateType.make || updateType == UpdateType.take) {
            orders.push(Order({
                exchangeAddress: ofExchange,
                orderId: orderId,
                updateType: updateType,
                makerAsset: orderAddresses[0],
                takerAsset: orderAddresses[1],
                makerQuantity: orderValues[0],
                takerQuantity: orderValues[1],
                timestamp: block.timestamp,
                fillTakerQuantity: orderValues[2]
            }));
        }
    }

    function updateAndGetQuantityBeingTraded(address _asset) external returns (uint) {
        uint quantityHere = IERC20(_asset).balanceOf(address(this));
        return add(updateAndGetQuantityHeldInExchange(_asset), quantityHere);
    }

    function updateAndGetQuantityHeldInExchange(address ofAsset) public returns (uint) {
        uint totalSellQuantity; // quantity in custody across exchanges
        uint totalSellQuantityInApprove; // quantity of asset in approve (allowance) but not custody of exchange
        for (uint i; i < exchanges.length; i++) {
            if (exchangesToOpenMakeOrders[exchanges[i].exchange][ofAsset].id == 0) {
                continue;
            }
            address sellAsset;
            uint remainingSellQuantity;
            (sellAsset, , remainingSellQuantity, ) =
                ExchangeAdapter(exchanges[i].adapter)
                .getOrder(
                    exchanges[i].exchange,
                    exchangesToOpenMakeOrders[exchanges[i].exchange][ofAsset].id,
                    ofAsset
                );
            if (remainingSellQuantity == 0) {    // remove id if remaining sell quantity zero (closed)
                _removeOpenMakeOrder(exchanges[i].exchange, ofAsset);
            }
            totalSellQuantity = add(totalSellQuantity, remainingSellQuantity);
            if (!exchanges[i].takesCustody) {
                totalSellQuantityInApprove += remainingSellQuantity;
            }
        }
        if (totalSellQuantity == 0) {
            isInOpenMakeOrder[ofAsset] = false;
        }
        return sub(totalSellQuantity, totalSellQuantityInApprove); // Since quantity in approve is not actually in custody
    }

    function returnBatchToVault(address[] memory _tokens) public {
        for (uint i = 0; i < _tokens.length; i++) {
            returnAssetToVault(_tokens[i]);
        }
    }

    function returnAssetToVault(address _token) public {
        require(
            msg.sender == address(this) || msg.sender == hub.manager() || hub.isShutDown(),
            "Sender is not this contract or manager"
        );
        safeTransfer(_token, routes.vault, IERC20(_token).balanceOf(address(this)));
    }

    function getExchangeInfo() public view returns (address[] memory, address[] memory, bool[] memory) {
        address[] memory ofExchanges = new address[](exchanges.length);
        address[] memory ofAdapters = new address[](exchanges.length);
        bool[] memory takesCustody = new bool[](exchanges.length);
        for (uint i = 0; i < exchanges.length; i++) {
            ofExchanges[i] = exchanges[i].exchange;
            ofAdapters[i] = exchanges[i].adapter;
            takesCustody[i] = exchanges[i].takesCustody;
        }
        return (ofExchanges, ofAdapters, takesCustody);
    }

    function getOpenOrderInfo(address ofExchange, address ofAsset) public view returns (uint, uint, uint) {
        OpenMakeOrder memory order = exchangesToOpenMakeOrders[ofExchange][ofAsset];
        return (order.id, order.expiresAt, order.orderIndex);
    }

    function isOrderExpired(address exchange, address asset) public view returns(bool) {
        return (
            exchangesToOpenMakeOrders[exchange][asset].expiresAt <= block.timestamp &&
            exchangesToOpenMakeOrders[exchange][asset].expiresAt > 0
        );
    }

    function getOrderDetails(uint orderIndex) public view returns (address, address, uint, uint) {
        Order memory order = orders[orderIndex];
        return (order.makerAsset, order.takerAsset, order.makerQuantity, order.takerQuantity);
    }

    function getZeroExV2OrderDetails(bytes32 orderId) public view returns (IZeroExV2.Order memory) {
        return orderIdToZeroExV2Order[orderId];
    }

    function getZeroExV3OrderDetails(bytes32 orderId) public view returns (IZeroExV3.Order memory) {
        return orderIdToZeroExV3Order[orderId];
    }

    function getOpenMakeOrdersAgainstAsset(address _asset) external view returns (uint256) {
        return openMakeOrdersAgainstAsset[_asset];
    }
}

contract TradingFactory is Factory {
    event NewInstance(
        address indexed hub,
        address indexed instance,
        address[] exchanges,
        address[] adapters,
        address registry
    );

    function createInstance(
        address _hub,
        address[] memory _exchanges,
        address[] memory _adapters,
        address _registry
    ) public returns (address) {
        address trading = address(new Trading(_hub, _exchanges, _adapters, _registry));
        childExists[trading] = true;
        emit NewInstance(
            _hub,
            trading,
            _exchanges,
            _adapters,
            _registry
        );
        return trading;
    }
}
