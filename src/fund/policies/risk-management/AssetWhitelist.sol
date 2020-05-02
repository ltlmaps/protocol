pragma solidity 0.6.8;

import "../AddressList.sol";
import "./CallOnIntegrationPostValidatePolicyBase.sol";

/// @title AssetWhitelist Contract
/// @author Melon Council DAO <security@meloncoucil.io>
/// @notice A whitelist of assets to add to a fund's vault
/// @dev Assets can be removed but not added from whitelist
contract AssetWhitelist is AddressList, CallOnIntegrationPostValidatePolicyBase {
    constructor(address[] memory _assets) public AddressList(_assets) {}

    function removeFromWhitelist(address _asset) external auth {
        require(isMember(_asset), "Asset not in whitelist");
        delete list[_asset];
        uint256 i = getAssetIndex(_asset);
        for (i; i < mirror.length-1; i++){
            mirror[i] = mirror[i+1];
        }
        mirror.pop();
    }

    function getAssetIndex(address _asset) public view returns (uint256) {
        for (uint256 i = 0; i < mirror.length; i++) {
            if (mirror[i] == _asset) { return i; }
        }
    }

    function rule(bytes calldata _encodedArgs) external view override returns (bool) {
        (,,address[] memory incomingAssets,,,) = __decodeRuleArgs(_encodedArgs);
        for (uint256 i = 0; i < incomingAssets.length; i++) {
            if (!isMember(incomingAssets[i])) return false;
        }

        return true;
    }
}
