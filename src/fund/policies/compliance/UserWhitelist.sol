pragma solidity 0.6.8;

import "../../../dependencies/DSAuth.sol";
import "./BuySharesPolicyBase.sol";

/// @title UserWhitelist Contract
/// @author Melon Council DAO <security@meloncoucil.io>
/// @notice Investors can be added and removed from whitelist
contract UserWhitelist is DSAuth, BuySharesPolicyBase {
    event ListAddition(address indexed who);
    event ListRemoval(address indexed who);

    mapping (address => bool) public whitelisted;

    constructor(address[] memory _preApproved) public {
        batchAddToWhitelist(_preApproved);
    }

    function addToWhitelist(address _who) public auth {
        whitelisted[_who] = true;
        emit ListAddition(_who);
    }

    function removeFromWhitelist(address _who) public auth {
        whitelisted[_who] = false;
        emit ListRemoval(_who);
    }

    function batchAddToWhitelist(address[] memory _members) public auth {
        for (uint256 i = 0; i < _members.length; i++) {
            addToWhitelist(_members[i]);
        }
    }

    function batchRemoveFromWhitelist(address[] memory _members) public auth {
        for (uint256 i = 0; i < _members.length; i++) {
            removeFromWhitelist(_members[i]);
        }
    }

    function rule(bytes calldata _encodedArgs) external view override returns (bool) {
        (address buyer,,,) = __decodeRuleArgs(_encodedArgs);
        return whitelisted[buyer];
    }
}
