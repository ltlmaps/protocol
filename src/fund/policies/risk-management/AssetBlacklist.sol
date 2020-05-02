pragma solidity 0.6.8;

import "../AddressList.sol";
import "./CallOnIntegrationPostValidatePolicyBase.sol";

/// @title AssetBlacklist Contract
/// @author Melon Council DAO <security@meloncoucil.io>
/// @notice A blacklist of assets to add to a fund's vault
/// @dev Assets can be added but not removed from blacklist
contract AssetBlacklist is AddressList, CallOnIntegrationPostValidatePolicyBase {
    constructor(address[] memory _assets) AddressList(_assets) public {}

    function addToBlacklist(address _asset) external auth {
        require(!isMember(_asset), "Asset already in blacklist");
        list[_asset] = true;
        mirror.push(_asset);
    }

    function rule(bytes calldata _encodedArgs) external view override returns (bool) {
        (,,address[] memory incomingAssets,,,) = __decodeRuleArgs(_encodedArgs);
        for (uint256 i = 0; i < incomingAssets.length; i++) {
            if (isMember(incomingAssets[i])) return false;
        }

        return true;
    }
}
