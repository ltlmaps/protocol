pragma solidity 0.6.1;

import "../dependencies/DSMath.sol";
import "../dependencies/token/IERC20.sol";
import "../prices/IPriceSource.sol";
import "../version/IVersion.sol";
import "./IEngine.sol";
import "../version/Registry.sol";

/// @notice inherit this to pay AMGU on a function call
abstract contract AmguConsumer is DSMath {

    /// @dev each of these must be implemented by the inheriting contract
    function engine() public view virtual returns (address);
    function mlnToken() public view virtual returns (address);
    function priceSource() public view virtual returns (address);
    function registry() public view virtual returns (address);

    event AmguPaid(address indexed payer, uint256 totalAmguPaidInEth, uint256 amguChargableGas, uint256 incentivePaid);

    /// @param deductIncentive whether to take into account an incentive external to AMGU
    modifier amguPayable(bool deductIncentive) {
        uint256 preGas = gasleft();
        _;
        uint256 postGas = gasleft();

        uint256 mlnPerAmgu = IEngine(engine()).getAmguPrice();
        uint256 mlnQuantity = mul(
            mlnPerAmgu,
            sub(preGas, postGas)
        );

        uint256 ethToPay = 0;
        if (mlnQuantity > 0) {
            ethToPay = IPriceSource(priceSource()).convertQuantity(
                mlnQuantity,
                mlnToken(),
                Registry(registry()).nativeAsset()
            );
        }

        uint256 incentiveAmount = 0;
        if (deductIncentive) {
            incentiveAmount = Registry(registry()).incentive();
        }

        require(
            msg.value >= add(ethToPay, incentiveAmount),
            "Insufficent AMGU and/or incentive"
        );
        IEngine(engine()).payAmguInEther.value(ethToPay)();

        require(
            msg.sender.send(
                sub(
                    sub(msg.value, ethToPay),
                    incentiveAmount
                )
            ),
            "Refund failed"
        );
        emit AmguPaid(msg.sender, ethToPay, sub(preGas, postGas), incentiveAmount);
    }
}
