pragma solidity 0.6.8;

import "./CallOnIntegrationPostValidatePolicyBase.sol";
import "../../hub/Hub.sol";
import "../../hub/Spoke.sol";
import "../../shares/Shares.sol";
import "../../../dependencies/DSMath.sol";
import "../../../prices/IValueInterpreter.sol";

/// @title MaxConcentration Contract
/// @author Melon Council DAO <security@meloncoucil.io>
/// @notice Validates concentration limitations per asset for its equity of a particular fund
contract MaxConcentration is DSMath, CallOnIntegrationPostValidatePolicyBase {
    uint256 internal constant ONE_HUNDRED_PERCENT = 10 ** 18;  // 100%
    uint256 public maxConcentration;

    constructor(uint256 _maxConcentration) public {
        require(
            _maxConcentration <= ONE_HUNDRED_PERCENT,
            "Max concentration cannot exceed 100%"
        );
        maxConcentration = _maxConcentration;
    }

    // TODO: Use live rates instead of canonical rates for fund and asset GAV
    // TODO: Need to assert price validity?
    function rule(bytes calldata _encodedArgs) external view override returns (bool) {
        Hub hub = Hub(Spoke(msg.sender).HUB());
        Shares shares = Shares(hub.shares());
        address denominationAsset = shares.DENOMINATION_ASSET();

        uint256 totalGav = shares.calcGav();
        (,,address[] memory incomingAssets,,,) = __decodeRuleArgs(_encodedArgs);
        uint256[] memory incomingAssetBalances = IVault(hub.vault()).getAssetBalances(incomingAssets);
        for (uint256 i = 0; i < incomingAssets.length; i++) {
            if (incomingAssets[i] == denominationAsset) continue;

            (
                uint256 assetGav,
                bool isValid
            ) = IValueInterpreter(IRegistry(hub.REGISTRY()).valueInterpreter())
                    .calcCanonicalAssetValue(
                        incomingAssets[i],
                        incomingAssetBalances[i],
                        denominationAsset
                    );

            require(assetGav > 0 && isValid, "calcGav: No valid price available for asset");

            if (__calcConcentration(assetGav, totalGav) > maxConcentration) return false;
        }

        return true;
    }

    function __calcConcentration(uint256 _assetGav, uint256 _totalGav)
        private
        pure
        returns (uint256)
    {
        return mul(_assetGav, ONE_HUNDRED_PERCENT) / _totalGav;
    }
}
