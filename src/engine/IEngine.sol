pragma solidity 0.6.1;


interface IEngine {
    function receiveIncentiveInEth() external payable;
    function payAmguInEther() external payable;
    function sellAndBurnMln(uint256 _mlnAmount) external;
    function getAmguPrice() external view returns (uint256);
}
