pragma solidity 0.6.4;

import "./DerivativePriceSourceBase.sol";

/// @title Chai Price Source
/// @author Melon Council DAO <security@meloncoucil.io>
/// @notice Price source oracle for Chai
/// @dev Calculation based on Chai source: https://github.com/dapphub/chai/blob/master/src/chai.sol
contract ChaiPriceSource is DerivativePriceSourceBase {
    IPot public DSR_POT;

    constructor(
        address[] memory _derivatives,
        address[] memory _denominationAssets,
        address _dsrPot
    )
        public
        DerivativePriceSourceBase(_derivatives, _denominationAssets)
    {
        DSR_POT = IPot(_dsrPot);
    }

    function __calcPrice(address _derivative) internal override returns (uint256) {
        assert(derivativeToDenominationAsset[_derivative] != address(0));
        uint256 chi = (now > DSR_POT.rho()) ? DSR_POT.drip() : DSR_POT.chi();
        return chi / 10 ** 9; // Refactor of mul(chi, 10 ** 18) / 10 ** 27
    }
}

/// @notice Limited interface for Maker DSR's Pot contract
/// @dev See DSR integration guide: https://github.com/makerdao/developerguides/blob/master/dai/dsr-integration-guide/dsr-integration-guide-01.md
interface IPot {
    function chi() external returns (uint256);
    function rho() external returns (uint256);
    function drip() external returns (uint256);
}
