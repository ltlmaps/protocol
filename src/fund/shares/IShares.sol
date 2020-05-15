pragma solidity 0.6.8;

/// @title Shares Interface
/// @author Melon Council DAO <security@meloncoucil.io>
interface IShares {
    function buyShares(address, address, uint256) external returns (uint256);
    function getSharesCostInAsset(uint256, address) external returns (uint256);
    function isSharesInvestmentAsset(address) external view returns (bool);
}

/// @title SharesFactory Interface
/// @author Melon Council DAO <security@meloncoucil.io>
interface ISharesFactory {
    function createInstance(
        address,
        address,
        address[] calldata,
        string calldata
    ) external returns (address);
}
