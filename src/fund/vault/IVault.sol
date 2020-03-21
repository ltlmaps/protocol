pragma solidity 0.6.4;

interface IVault {
    function assetBalances(address) external view returns (uint256);
    function decreaseAssetBalance(address, uint256) external;
    function deposit(address, uint256) external;
    function getOwnedAssets() external view returns (address[] memory);
    function increaseAssetBalance(address, uint256) external;
    function withdraw(address, uint256) external;
}

interface IVaultFactory {
     function createInstance(
        address,
        address[] calldata,
        address
    ) external returns (address);
}
