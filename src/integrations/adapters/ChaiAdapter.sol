pragma solidity 0.6.4;
pragma experimental ABIEncoderV2;

import "../libs/Lender.sol";
import "../interfaces/IChai.sol";

/// @title ChaiAdapter Contract
/// @author Melon Council DAO <security@meloncoucil.io>
/// @notice Adapter for Chai <https://github.com/dapphub/chai>
contract ChaiAdapter is Lender {
    function __fillLend(
        address _targetContract,
        bytes memory _encodedArgs,
        bytes memory _fillData
    )
        internal
        override
        validateAndFinalizeFilledOrder(_targetContract, _fillData)
    {
        (,uint256 daiQuantity,) = __decodeLendArgs(_encodedArgs);

        // Execute Lend on Chai
        IChai(_targetContract).join(address(this), daiQuantity);
    }

    function __fillRedeem(
        address _targetContract,
        bytes memory _encodedArgs,
        bytes memory _fillData
    )
        internal
        override
        validateAndFinalizeFilledOrder(_targetContract, _fillData)
    {
        (uint256 chaiQuantity,,) = __decodeRedeemArgs(_encodedArgs);

        // Execute Redeem on Chai
        IChai(_targetContract).exit(address(this), chaiQuantity);
    }

    function __formatLendFillOrderArgs(
        address _targetContract,
        bytes memory _encodedArgs
    )
        internal
        view
        override
        returns (address[] memory, uint256[] memory, address[] memory)
    {
        (
            address daiAddress,
            uint256 daiQuantity,
            uint256 minChaiQuantity
        ) = __decodeLendArgs(_encodedArgs);

        address[] memory fillAssets = new address[](2);
        fillAssets[0] = _targetContract; // Receive derivative
        fillAssets[1] = daiAddress; // Lend asset

        uint256[] memory fillExpectedAmounts = new uint256[](2);
        fillExpectedAmounts[0] = minChaiQuantity; // Receive derivative
        fillExpectedAmounts[1] = daiQuantity; // Lend asset

        address[] memory fillApprovalTargets = new address[](2);
        fillApprovalTargets[0] = address(0); // Fund (Use 0x0)
        fillApprovalTargets[1] = _targetContract; // Chai contract

        return (fillAssets, fillExpectedAmounts, fillApprovalTargets);
    }

    function __formatRedeemFillOrderArgs(
        address _targetContract,
        bytes memory _encodedArgs
    )
        internal
        view
        override
        returns (address[] memory, uint256[] memory, address[] memory)
    {
        (
            uint256 chaiQuantity,
            address daiAddress,
            uint256 minDaiQuantity
        ) = __decodeRedeemArgs(_encodedArgs);

        address[] memory fillAssets = new address[](2);
        fillAssets[0] = daiAddress; // Receive asset
        fillAssets[1] = _targetContract; // Redeem derivative

        uint256[] memory fillExpectedAmounts = new uint256[](2);
        fillExpectedAmounts[0] = minDaiQuantity; // Receive derivative
        fillExpectedAmounts[1] = chaiQuantity; // Lend asset

        address[] memory fillApprovalTargets = new address[](2);
        fillApprovalTargets[0] = address(0); // Fund (Use 0x0)
        fillApprovalTargets[1] = _targetContract; // Chai contract

        return (fillAssets, fillExpectedAmounts, fillApprovalTargets);
    }

    function __validateLendParams(
        address _targetContract,
        bytes memory _encodedArgs
    )
        internal
        view
        override
    {
        require(_targetContract != address(0));
        (
            address daiAddress,
            uint256 daiQuantity,
            uint256 minChaiQuantity
        ) = __decodeLendArgs(_encodedArgs);
        require(daiAddress != address(0));
        require(daiQuantity > 0);
        require(minChaiQuantity > 0);
    }

    function __validateRedeemParams(
        address _targetContract,
        bytes memory _encodedArgs
    )
        internal
        view
        override
    {
        require(_targetContract != address(0));
        (
            uint256 chaiQuantity,
            address daiAddress,
            uint256 minDaiQuantity
        ) = __decodeRedeemArgs(_encodedArgs);
        require(daiAddress != address(0));
        require(chaiQuantity > 0);
        require(minDaiQuantity > 0);
    }

    // PRIVATE FUNCTIONS

    function __decodeLendArgs(bytes memory _encodedArgs)
        private
        pure
        returns (
            address daiAddress_,
            uint256 daiQuantity_,
            uint256 minChaiQuantity_
        )
    {
        return abi.decode(_encodedArgs, (address,uint256,uint256));
    }

    function __decodeRedeemArgs(bytes memory _encodedArgs)
        private
        pure
        returns (
            uint256 chaiQuantity_,
            address daiAddress_,
            uint256 minDaiQuantity_
        )
    {
        return abi.decode(_encodedArgs, (uint256,address,uint256));
    }
}
