pragma solidity 0.6.8;

/// @title Policy Interface
/// @author Melon Council DAO <security@meloncoucil.io>
interface IPolicy {
    function rule(bytes calldata) external view returns (bool);
}
