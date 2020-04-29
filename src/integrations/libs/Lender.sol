pragma solidity 0.6.4;

import "./OrderFiller.sol";

/// @title Lender base contract
/// @author Melon Council DAO <security@meloncoucil.io>
/// @notice Base contract for Lending adapters in Melon Funds
abstract contract Lender is OrderFiller {
    function lend(address _targetContract, bytes memory _encodedArgs) public {
        __validateLendParams(_targetContract, _encodedArgs);

        (
            address[] memory fillAssets,
            uint256[] memory fillExpectedAmounts,
            address[] memory fillApprovalTargets
        ) = __formatLendFillOrderArgs(
            _targetContract,
            _encodedArgs
        );

        __fillLend(
            _targetContract,
            _encodedArgs,
            __encodeOrderFillData(fillAssets, fillExpectedAmounts, fillApprovalTargets)
        );
    }

    function redeem(address _targetContract, bytes memory _encodedArgs) public {
        __validateRedeemParams(_targetContract, _encodedArgs);

        (
            address[] memory fillAssets,
            uint256[] memory fillExpectedAmounts,
            address[] memory fillApprovalTargets
        ) = __formatRedeemFillOrderArgs(
            _targetContract,
            _encodedArgs
        );

        __fillRedeem(
            _targetContract,
            _encodedArgs,
            __encodeOrderFillData(fillAssets, fillExpectedAmounts, fillApprovalTargets)
        );
    }

    // INTERNAL FUNCTIONS

    function __fillLend(
        address _targetContract,
        bytes memory _encodedArgs,
        bytes memory _fillData
    )
        internal
        virtual;

    function __fillRedeem(
        address _targetContract,
        bytes memory _encodedArgs,
        bytes memory _fillData
    )
        internal
        virtual;

    function __formatLendFillOrderArgs(
        address _targetContract,
        bytes memory _encodedArgs
    )
        internal
        view
        virtual
        returns (
            address[] memory fillAssets_,
            uint256[] memory fillExpectedAmounts_,
            address[] memory fillApprovalTargets_
        );

    function __formatRedeemFillOrderArgs(
        address _targetContract,
        bytes memory _encodedArgs
    )
        internal
        view
        virtual
        returns (
            address[] memory fillAssets_,
            uint256[] memory fillExpectedAmounts_,
            address[] memory fillApprovalTargets_
        );

    function __validateLendParams(
        address _targetContract,
        bytes memory _encodedArgs
    )
        internal
        view
        virtual;

    function __validateRedeemParams(
        address _targetContract,
        bytes memory _encodedArgs
    )
        internal
        view
        virtual;
}
