pragma solidity 0.6.8;
pragma experimental ABIEncoderV2;

import "../../dependencies/libs/EnumerableSet.sol";
import "../../dependencies/TokenUser.sol";
import "../../integrations/libs/IIntegrationAdapter.sol";
import "../hub/Spoke.sol";
import "./IVault.sol";

/// @title Vault Contract
/// @author Melon Council DAO <security@meloncoucil.io>
/// @notice Stores fund assets and plugs into external services via integrations
contract Vault is IVault, TokenUser, Spoke {
    using EnumerableSet for EnumerableSet.AddressSet;

    event AdaptersDisabled (address[] adapters);

    event AdaptersEnabled (address[] adapters);

    event AssetAdded(address asset);

    event AssetBalanceUpdated(address indexed asset, uint256 oldBalance, uint256 newBalance);

    event AssetRemoved(address asset);

    event CallOnIntegrationExecuted(
        address adapter,
        address gateway,
        uint256 integrationTypeIndex,
        address[] incomingAssets,
        uint256[] incomingAssetAmounts,
        address[] outgoingAssets,
        uint256[] outgoingAssetAmounts
    );

    // This info is pulled from Registry
    // Better for fund to maintain its own copy in case the info changes on the Registry
    struct IntegrationInfo {
        address gateway;
        uint256 typeIndex;
    }

    uint8 constant public MAX_OWNED_ASSETS = 20; // TODO: Keep this?
    address[] public ownedAssets;
    mapping(address => uint256) public override assetBalances;

    EnumerableSet.AddressSet private enabledAdapters;
    mapping (address => IntegrationInfo) public adapterToIntegrationInfo;

    constructor(address _hub, address[] memory _adapters) public Spoke(_hub) {
        if (_adapters.length > 0) {
            __enableAdapters(_adapters);
        }
    }

    // EXTERNAL FUNCTIONS

    /// @notice Receive ether function (used to receive ETH in intermediary adapter steps)
    receive() external payable {}

    /// @notice Deposits an asset into the Vault
    /// @dev Only the Shares contract can call this function
    /// @param _asset The asset to deposit
    /// @param _amount The amount of the asset to deposit
    function deposit(address _asset, uint256 _amount) external override onlyShares {
        __increaseAssetBalance(_asset, _amount);
        __safeTransferFrom(_asset, msg.sender, address(this), _amount);
    }

    /// @notice Disable integration adapters from use in the fund
    /// @param _adapters The adapters to disable
    function disableAdapters(address[] calldata _adapters) external onlyManager {
        for (uint256 i = 0; i < _adapters.length; i++) {
            require(__adapterIsEnabled(_adapters[i]), "disableAdapters: adapter already disabled");
            EnumerableSet.remove(enabledAdapters, _adapters[i]);
            delete adapterToIntegrationInfo[_adapters[i]];
        }
        emit AdaptersDisabled(_adapters);
    }

    /// @notice Enable integration adapters from use in the fund
    /// @param _adapters The adapters to enable
    function enableAdapters(address[] calldata _adapters) external onlyManager {
        require(_adapters.length > 0, "enableAdapters: _adapters cannot be empty");
        __enableAdapters(_adapters);
    }

    /// @notice Get a list of enabled adapters
    /// @return An array of enabled adapter addresses
    function getEnabledAdapters() external view returns (address[] memory) {
        return EnumerableSet.enumerate(enabledAdapters);
    }

    /// @notice Retrieves the assets owned by the fund
    /// @return The addresses of assets owned by the fund
    function getOwnedAssets() external view override returns(address[] memory) {
        return ownedAssets;
    }

    /// @notice Withdraw an asset from the Vault
    /// @dev Only the Shares contract can call this function
    /// @param _asset The asset to withdraw
    /// @param _amount The amount of the asset to withdraw
    function withdraw(address _asset, uint256 _amount) external override onlyShares {
        __decreaseAssetBalance(_asset, _amount);
        __safeTransfer(_asset, msg.sender, _amount);
    }

    // PUBLIC FUNCTIONS

    /// @notice Universal method for calling third party contract functions through adapters
    /// @dev Refer to specific adapter to see how to encode its arguments
    /// @param _adapter Adapter of the integration on which to execute a call
    /// @param _methodSignature Method signature of the adapter method to execute
    /// @param _encodedArgs Encoded arguments specific to the adapter
    function callOnIntegration(
        address _adapter,
        string memory _methodSignature,
        bytes memory _encodedArgs
    )
        public // TODO: leaving as public because it will need this for multiCallOnIntegration
        onlyManager
    {
        require(
            __getHub().status() == IHub.FundStatus.Active,
            "callOnIntegration: Hub must be active"
        );
        require(
            __adapterIsEnabled(_adapter),
            "callOnIntegration: Adapter is not enabled for fund"
        );
        bytes4 selector = bytes4(keccak256(bytes(_methodSignature)));

        // Pre-validate against fund policies
        IPolicyManager policyManager = __getPolicyManager();
        policyManager.preValidate(
            IPolicyManager.PolicyHook.CallOnIntegration,
            abi.encode(selector, _adapter)
        );

        // Get balances for assets to compare with post-call balances
        address[] memory monitoredAssets = __getCoIMonitoredAssets(
            IIntegrationAdapter(_adapter).parseIncomingAssets(selector, _encodedArgs)
        );
        uint256[] memory preCallMonitoredAssetBalances = getAssetBalances(monitoredAssets);

        // Execute call on integration adapter
        __executeCoI(_adapter, _methodSignature, _encodedArgs);

        // Update assetBalances and parse incoming and outgoing asset info
        (
            address[] memory incomingAssets,
            uint256[] memory incomingAssetAmounts,
            address[] memory outgoingAssets,
            uint256[] memory outgoingAssetAmounts
        ) = __updatePostCoIBalances(
            monitoredAssets,
            preCallMonitoredAssetBalances
        );

        // Post-validate against fund policies
        policyManager.postValidate(
            IPolicyManager.PolicyHook.CallOnIntegration,
            abi.encode(
                selector,
                _adapter,
                incomingAssets,
                incomingAssetAmounts,
                outgoingAssets,
                outgoingAssetAmounts
            )
        );

        IntegrationInfo memory integrationInfo = adapterToIntegrationInfo[_adapter];
        emit CallOnIntegrationExecuted(
            _adapter,
            integrationInfo.gateway,
            integrationInfo.typeIndex,
            incomingAssets,
            incomingAssetAmounts,
            outgoingAssets,
            outgoingAssetAmounts
        );
    }

    function getAssetBalances(address[] memory _assets)
        public
        view
        override
        returns (uint256[] memory balances_)
    {
        balances_ = new uint256[](_assets.length);
        for (uint256 i = 0; i < _assets.length; i++) {
            balances_[i] = assetBalances[_assets[i]];
        }
    } 

    // PRIVATE FUNCTIONS
    /// @notice Check is an adapter is enabled for the fund
    function __adapterIsEnabled(address _adapter) private view returns (bool) {
        return EnumerableSet.contains(enabledAdapters, _adapter);
    }

    /// @notice Adds an asset to a fund's ownedAssets
    function __addAssetToOwnedAssets(address _asset) private {
        require(
            ownedAssets.length < MAX_OWNED_ASSETS,
            "Max owned asset limit reached"
        );
        ownedAssets.push(_asset);
        emit AssetAdded(_asset);
    }

    /// @notice Decreases the balance of an asset in a fund's internal system of account
    function __decreaseAssetBalance(address _asset, uint256 _amount) private {
        require(_amount > 0, "__decreaseAssetBalance: _amount must be > 0");
        require(_asset != address(0), "__decreaseAssetBalance: _asset cannot be empty");

        uint256 oldBalance = assetBalances[_asset];
        require(
            oldBalance >= _amount,
            "__decreaseAssetBalance: new balance cannot be less than 0"
        );

        uint256 newBalance = sub(oldBalance, _amount);
        if (newBalance == 0) __removeFromOwnedAssets(_asset);
        assetBalances[_asset] = newBalance;

        emit AssetBalanceUpdated(_asset, oldBalance, newBalance);
    }

    /// @notice Enable adapters for use in the fund
    /// @dev Fails if an already-enabled adapter is passed;
    /// important to assure Integration Info is not unintentionally updated from Registry
    function __enableAdapters(address[] memory _adapters) private {
        IRegistry registry = __getRegistry();
        for (uint256 i = 0; i < _adapters.length; i++) {
            require(
                registry.integrationAdapterIsRegistered(_adapters[i]),
                "__enableAdapters: Adapter is not on Registry"
            );
            require(
                !__adapterIsEnabled(_adapters[i]),
                "__enableAdapters: Adapter is already enabled"
            );

            // Pull adapter info from registry
            adapterToIntegrationInfo[_adapters[i]] = IntegrationInfo({
                gateway: registry.adapterToIntegrationInfo(_adapters[i]).gateway,
                typeIndex: registry.adapterToIntegrationInfo(_adapters[i]).typeIndex
            });
            EnumerableSet.add(enabledAdapters, _adapters[i]);
        }
        emit AdaptersEnabled(_adapters);
    }

    function __executeCoI(
        address _adapter,
        string memory _methodSignature,
        bytes memory _encodedArgs
    )
        private
    {
        (bool success, bytes memory returnData) = _adapter.delegatecall(
            abi.encodeWithSignature(
                _methodSignature,
                adapterToIntegrationInfo[_adapter].gateway,
                _encodedArgs
            )
        );
        require(success, string(returnData));
    }

    // TODO: can check uniqueness of incoming assets also
    /// @dev Combining ownedAssets and new incoming assets is necessary because some asset might
    /// have an ERC20 balance but not an assetBalance (e.g., if someone sends assets directly to a vault
    /// to try and game performance metrics)
    function __getCoIMonitoredAssets(address[] memory expectedIncomingAssets)
        private
        view
        returns (address[] memory monitoredAssets_)
    {
        // Get count of untracked incoming assets
        uint256 newIncomingAssetsCount;
        for (uint256 i = 0; i < expectedIncomingAssets.length; i++) {
            if (assetBalances[expectedIncomingAssets[i]] == 0) {
                newIncomingAssetsCount++;
            }
        }
        // Create an array of ownedAssets + untracked incoming assets
        monitoredAssets_ = new address[](ownedAssets.length + newIncomingAssetsCount);
        for (uint256 i = 0; i < ownedAssets.length; i++) {
            monitoredAssets_[i] = ownedAssets[i];
        }

        for (uint256 i = 0; i < expectedIncomingAssets.length; i++) {
            if (assetBalances[expectedIncomingAssets[i]] == 0) {
                monitoredAssets_[ownedAssets.length + i] = expectedIncomingAssets[i];
            }
        }
    }

    /// @notice Increases the balance of an asset in a fund's internal system of account
    function __increaseAssetBalance(address _asset, uint256 _amount) private {
        require(_amount > 0, "__increaseAssetBalance: _amount must be > 0");
        require(_asset != address(0), "__increaseAssetBalance: _asset cannot be empty");

        uint256 oldBalance = assetBalances[_asset];
        if (oldBalance == 0) __addAssetToOwnedAssets(_asset);
        uint256 newBalance = add(oldBalance, _amount);
        assetBalances[_asset] = newBalance;

        emit AssetBalanceUpdated(_asset, oldBalance, newBalance);
    }

    /// @notice Confirm whether an asset is receivable via an integration
    function __isReceivableAsset(address _asset) private view returns (bool) {
        IRegistry registry = __getRegistry();
        if (
            registry.assetIsRegistered(_asset) ||
            registry.derivativeToPriceSource(_asset) != address(0)
        ) return true;
        return false;
    }

    /// @notice Removes an asset from a fund's ownedAssets
    function __removeFromOwnedAssets(address _asset) private {
        for (uint256 i; i < ownedAssets.length; i++) {
            if (ownedAssets[i] == _asset) {
                ownedAssets[i] = ownedAssets[ownedAssets.length - 1];
                ownedAssets.pop();
                break;
            }
        }
        emit AssetRemoved(_asset);
    }

    // TODO: assert uniqueness of each item in assets, or protect against this earlier
    function __updatePostCoIBalances(
        address[] memory _assets,
        uint256[] memory _initialBalances
    )
        private
        returns (
            address[] memory incomingAssets_,
            uint256[] memory incomingAssetAmounts_,
            address[] memory outgoingAssets_,
            uint256[] memory outgoingAssetAmounts_
        )
    {
        // 1. Get counts of outgoing assets and incoming assets,
        // along with storing balances diffs in memory
        uint256[] memory balanceDiffs = new uint256[](_assets.length);
        bool[] memory balancesIncreased = new bool[](_assets.length);
        uint256 outgoingAssetsCount;
        uint256 incomingAssetsCount;

        for (uint256 i = 0; i < _assets.length; i++) {
            address asset = _assets[i];
            uint256 oldBalance = _initialBalances[i];
            uint256 newBalance = IERC20(asset).balanceOf(address(this));
            if (newBalance < oldBalance) {
                balanceDiffs[i] = sub(oldBalance, newBalance);
                outgoingAssetsCount++;
            }
            else if (newBalance > oldBalance) {
                require(__isReceivableAsset(asset), "__updatePostCoIBalances: unreceivable asset detected");
                balanceDiffs[i] = sub(newBalance, oldBalance);
                balancesIncreased[i] = true;
                incomingAssetsCount++;
            }
        }

        // 2. Construct arrays of incoming and outgoing assets
        incomingAssets_ = new address[](incomingAssetsCount);
        incomingAssetAmounts_ = new uint256[](incomingAssetsCount);
        outgoingAssets_ = new address[](outgoingAssetsCount);
        outgoingAssetAmounts_ = new uint256[](outgoingAssetsCount);
        uint256 incomingAssetIndex;
        uint256 outgoingAssetIndex;

        for (uint256 i = 0; i < _assets.length; i++) {
            if (balanceDiffs[i] > 0) {
                if (balancesIncreased[i]) {
                    incomingAssets_[incomingAssetIndex] = _assets[i];
                    incomingAssetAmounts_[incomingAssetIndex] = balanceDiffs[i];
                    incomingAssetIndex++;
                    __increaseAssetBalance(_assets[i], balanceDiffs[i]);
                }
                else {
                    outgoingAssets_[outgoingAssetIndex] = _assets[i];
                    outgoingAssetAmounts_[outgoingAssetIndex] = balanceDiffs[i];
                    outgoingAssetIndex++;
                    __decreaseAssetBalance(_assets[i], balanceDiffs[i]);
                }
            }
        }
    }
}

contract VaultFactory {
    function createInstance(address _hub, address[] calldata _adapters)
        external
        returns (address)
    {
        return address(new Vault(_hub, _adapters));
    }
}
