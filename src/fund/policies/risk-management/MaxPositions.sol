pragma solidity 0.6.8;

import "../../hub/Spoke.sol";
import "../../vault/Vault.sol";
import "./CallOnIntegrationPostValidatePolicyBase.sol";

/// @title MaxPositions Contract
/// @author Melon Council DAO <security@meloncoucil.io>
/// @notice Validates the allowed number of owned assets of a particular fund
contract MaxPositions is CallOnIntegrationPostValidatePolicyBase {
    uint256 public maxPositions;

    /// @dev _maxPositions = 10 means max 10 different asset tokens
    /// @dev _maxPositions = 0 means no asset tokens are investable
    constructor(uint256 _maxPositions) public { maxPositions = _maxPositions; }

    // TODO: Revisit allowing denomination asset to pass,
    // though there are problems with ownedAssets becoming larger than maxPositions
    function rule(bytes calldata) external view override returns (bool) {
        IHub hub = IHub(Spoke(msg.sender).HUB());
        return Vault(payable(hub.vault())).getOwnedAssets().length <= maxPositions;
    }
}
