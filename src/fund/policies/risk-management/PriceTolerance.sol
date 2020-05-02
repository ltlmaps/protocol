pragma solidity 0.6.8;

import "./CallOnIntegrationPostValidatePolicyBase.sol";
import "../../hub/Hub.sol";
import "../../hub/Spoke.sol";
import "../../../dependencies/DSMath.sol";
import "../../../fund/shares/Shares.sol";
import "../../../prices/IValueInterpreter.sol";
import "../../../registry/Registry.sol";

/// @title PriceTolerance Contract
/// @author Melon Council DAO <security@meloncoucil.io>
/// @notice Validate the price tolerance of a trade
contract PriceTolerance is DSMath, CallOnIntegrationPostValidatePolicyBase {
    uint256 public tolerance;

    uint256 constant MULTIPLIER = 10 ** 16; // to give effect of a percentage
    uint256 constant DIVISOR = 10 ** 18;

    // _tolerance: 10 equals to 10% of tolerance
    constructor(uint256 _tolerancePercent) public {
        require(_tolerancePercent <= 100, "Tolerance range is 0% - 100%");
        tolerance = mul(_tolerancePercent, MULTIPLIER);
    }

    function rule(bytes calldata _encodedArgs) external view override returns (bool) {
        (
            ,
            ,
            address[] memory incomingAssets,
            uint256[] memory incomingAmounts,
            address[] memory outgoingAssets,
            uint256[] memory outgoingAmounts
        ) = __decodeRuleArgs(_encodedArgs);

        uint256 incomingAssetsValue = __calcCumulativeAssetsValue(incomingAssets, incomingAmounts);
        uint256 outgoingAssetsValue = __calcCumulativeAssetsValue(outgoingAssets, outgoingAmounts);

        // Only check case where there is more outgoing value
        if (incomingAssetsValue >= outgoingAssetsValue) return true;

        // Tolerance threshold is 'value defecit over total value of incoming assets'
        uint256 diff = sub(outgoingAssetsValue, incomingAssetsValue);
        if (mul(diff, DIVISOR) / incomingAssetsValue <= tolerance) return true;

        return false;
    }

    function __calcCumulativeAssetsValue(address[] memory _assets, uint256[] memory _amounts)
        private
        view
        returns (uint256 cumulativeValue_)
    {
        Hub hub = Hub(Spoke(msg.sender).HUB());
        address denominationAsset = Shares(hub.shares()).DENOMINATION_ASSET();

        for (uint256 i = 0; i < _assets.length; i++) {
            (
                uint256 assetValue,
                bool isValid
            ) = IValueInterpreter(IRegistry(hub.REGISTRY()).valueInterpreter())
                    .calcLiveAssetValue(
                    _assets[i],
                    _amounts[i],
                    denominationAsset
                );
            require(assetValue > 0 && isValid, "calcGav: No valid price available for asset");
            cumulativeValue_ = add(cumulativeValue_, assetValue);
        }
    }
}
