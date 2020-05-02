pragma solidity 0.6.8;

import "../IPolicy.sol";

/// @title BuySharesPolicyBase Contract
/// @author Melon Council DAO <security@meloncoucil.io>
/// @notice A base contract for policies implemented while buying shares
abstract contract BuySharesPolicyBase is IPolicy {
    function __decodeRuleArgs(bytes memory _encodedArgs)
        internal
        pure
        returns (
            address buyer_,
            address investmentAsset_,
            address investmentAssetQuantity_,
            uint256 sharesQuantity_
        )
    {
        return abi.decode(
            _encodedArgs,
            (
                address,
                address,
                address,
                uint256
            )
        );
    }
}
