pragma solidity 0.6.12;

// Ownable
interface IBalanceAllocator {
    /// @dev Events should emit the current price in USD of the Balance withdrawn
    function withdrawAllocation(uint256 aid, uint256 amount) external; // onlyAllocationAdmin or Owner
    function withdrawAllocationTo(uint256 aid, uint256 amount, address to) external; // onlyAllocationAdmin or Owner
    function syncAllocations() external; // only after delay?
    function setSyncDelay() external; // onlyOwner
    function addAllocation(string memory name, uint256 allocation, address[] memory allocationAdmins) external; // onlyOwner
    function setAllocation(uint256 aid, uint256 allocation) external; // onlyOwner
    function addAdminsToAllocation(uint256 aid, address[] memory newAllocationAdmins) external; // onlyOwner
    function removeAdminsFromAllocation(uint256 aid, address[] memory allocationAdminsToRemove) external; // onlyOwner
    /// @dev Transfers the MasterBalance dev address to the owner of this contract
    function transferDevToOwner() external; // onlyOwner
    function sweepToken() external; //onlyOwner
}