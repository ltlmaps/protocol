pragma solidity 0.6.4;

import "../IDerivativePriceSource.sol";

/// @title DerivativePriceSourceBase Contract
/// @author Melon Council DAO <security@meloncoucil.io>
/// @notice Base implementation for derivative price source oracle implementations
abstract contract DerivativePriceSourceBase is IDerivativePriceSource {
    uint256 public override lastUpdated;
    address[] internal derivatives;
    mapping (address => address) internal derivativeToDenominationAsset;
    mapping (address => uint256) internal derivativeToPrice;

    event PriceUpdated(address indexed derivative, address denominationAsset, uint256 price);

    constructor(address[] memory _derivatives, address[] memory _denominationAssets) public {
        require(
            _derivatives.length == _denominationAssets.length,
            "constructor: unequal number of derivatives and denomination assets"
        );

        for (uint256 i = 0; i < _derivatives.length; i++) {
            derivatives.push(_derivatives[i]);
            derivativeToDenominationAsset[_derivatives[i]] = _denominationAssets[i];
        }

        update(); // TODO: do we want to do this?
    }

    function getPrice(address _derivative)
        external
        view
        override
        returns (address, uint256)
    {
        return (derivativeToDenominationAsset[_derivative], derivativeToPrice[_derivative]);
    }

    function update() public override {
        // TODO: Do we want to use access control?
        // require(
        //     msg.sender == registry.owner() || msg.sender == updater,
        //     "update: Only registry owner or updater can call"
        // );
        require(derivatives.length > 0, "update: no derivatives registered");

        for (uint256 i = 0; i < derivatives.length; i++) {
            uint256 price = __calcPrice(derivatives[i]);
            assert(price != 0);
            derivativeToPrice[derivatives[i]] = price;

            emit PriceUpdated(
                derivatives[i],
                derivativeToDenominationAsset[derivatives[i]],
                price
            );
        }
        lastUpdated = now;
    }

    function __calcPrice(address _derivative) internal virtual returns (uint256);
}
