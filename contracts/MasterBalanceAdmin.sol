// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;




import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IMasterBalance.sol";

/// @title Admin MasterBalance proxy contract used to add features to MasterBalance admin functions
/// @dev This contract does NOT handle changing the dev address of the MasterBalance because that can only be done
///  by the dev address itself
/// @author DeFiFoFum (Balancetastic)
/// @notice Admin functions are separated into onlyOwner and onlyFarmAdmin to separate concerns
contract MasterBalanceAdmin is Ownable {
    using SafeMath for uint256;

    struct FixedPercentFarmInfo {
        uint256 pid;
        uint256 allocationPercent;
        bool isActive;
    }

    /// @notice Farm admin can manage master Balance farms and fixed percent farms
    address public farmAdmin;
    /// @notice MasterBalance Address
    IMasterBalance immutable public masterBalance;
    /// @notice Address which is eligible to accept ownership of the MasterBalance. Set by the current owner.
    address public pendingMasterBalanceOwner = address(0);
    /// @notice Array of MasterBalance pids that are active fixed percent farms
    uint256[] public fixedPercentFarmPids;
    /// @notice mapping of MasterBalance pids to FixedPercentFarmInfo
    mapping(uint256 => FixedPercentFarmInfo) public getFixedPercentFarmFromPid;
    /// @notice The percentages are divided by 10000
    uint256 constant public PERCENTAGE_PRECISION = 1e4;
    /// @notice Percentage of base pool allocation managed by MasterBalance internally
    /// @dev The BASE_PERCENTAGE needs to be considered in fixed percent farm allocation updates as it's allocation is based on a percentage
    uint256 constant public BASE_PERCENTAGE = PERCENTAGE_PRECISION / 4; // The base staking pool always gets 25%
    /// @notice Approaching max fixed farm percentage makes the fixed farm allocations go to infinity
    uint256 constant public MAX_FIXED_FARM_PERCENTAGE_BUFFER = PERCENTAGE_PRECISION / 10; // 10% Buffer
    /// @notice Percentage available to additional fixed percent farms
    uint256 constant public MAX_FIXED_FARM_PERCENTAGE = PERCENTAGE_PRECISION - BASE_PERCENTAGE - MAX_FIXED_FARM_PERCENTAGE_BUFFER;
    /// @notice Total allocation percentage for fixed percent farms
    uint256 public totalFixedPercentFarmPercentage = 0;
    /// @notice Max multiplier which is possible to be set on the MasterBalance
    uint256 constant public MAX_BONUS_MULTIPLIER = 4;

    event SetPendingMasterBalanceOwner(address pendingMasterBalanceOwner);
    event AddFarm(IERC20 indexed lpToken, uint256 allocation);
    event SetFarm(uint256 indexed pid, uint256 allocation);
    event SyncFixedPercentFarm(uint256 indexed pid, uint256 allocation);
    event AddFixedPercentFarm(uint256 indexed pid, uint256 allocationPercentage);
    event SetFixedPercentFarm(uint256 indexed pid, uint256 previousAllocationPercentage, uint256 allocationPercentage);
    event TransferredFarmAdmin(address indexed previousFarmAdmin, address indexed newFarmAdmin);
    event SweepWithdraw(address indexed to, IERC20 indexed token, uint256 amount);


    constructor(
        IMasterBalance _masterBalance,
        address _farmAdmin
    ) public {
        masterBalance = _masterBalance;
        farmAdmin = _farmAdmin;
    }

    modifier onlyFarmAdmin() {
        require(msg.sender == farmAdmin, "must be called by farm admin");
        _;
    }

    /** External Functions  */

    /// @notice Set an address as the pending admin of the MasterBalance. The address must accept afterward to take ownership.
    /// @param _pendingMasterBalanceOwner Address to set as the pending owner of the MasterBalance.
    function setPendingMasterBalanceOwner(address _pendingMasterBalanceOwner) external onlyOwner {
        pendingMasterBalanceOwner = _pendingMasterBalanceOwner;
        emit SetPendingMasterBalanceOwner(pendingMasterBalanceOwner);
    }

    /// @notice The pendingMasterBalanceOwner takes ownership through this call
    /// @dev Transferring MasterBalance ownership away from this contract renders this contract useless. 
    function acceptMasterBalanceOwnership() external {
        require(msg.sender == pendingMasterBalanceOwner, "not pending owner");
        masterBalance.transferOwnership(pendingMasterBalanceOwner);
        pendingMasterBalanceOwner = address(0);
    }

    /// @notice Update the rewardPerBlock multiplier on the MasterBalance contract
    /// @param _newMultiplier Multiplier to change to
    function updateMasterBalanceMultiplier(uint256 _newMultiplier) external onlyOwner {
        require(_newMultiplier <= MAX_BONUS_MULTIPLIER, 'multiplier greater than max');
        masterBalance.updateMultiplier(_newMultiplier);
    }

    /// @notice Helper function to update MasterBalance pools in batches 
    /// @dev The MasterBalance massUpdatePools function uses a for loop which in the future
    ///  could reach the block gas limit making it incallable. 
    /// @param pids Array of MasterBalance pids to update
    function batchUpdateMasterBalancePools(uint256[] memory pids) external {
        for (uint256 pidIndex = 0; pidIndex < pids.length; pidIndex++) {
            masterBalance.updatePool(pids[pidIndex]);
        }
    }

    // @notice Obtain detailed allocation information regarding a MasterBalance pool
    // @param pid MasterBalance pid to pull detailed information from
    // @return lpToken Address of the stake token for this pool
    // @return poolAllocationPoint Allocation points for this pool
    // @return totalAllocationPoints Total allocation points across all pools
    // @return poolAllocationPercentMantissa Percentage of pool allocation points to total multiplied by 1e18
    // @return poolBalancerBlock Amount of Balance given to the pool per block
    // @return poolBalancerDay Amount of Balance given to the pool per day
    // @return poolBalancerMonth Amount of Balance given to the pool per month
    function getDetailedPoolInfo(uint pid) external view returns (
        address lpToken,
        uint256 poolAllocationPoint,
        uint256 totalAllocationPoints,
        uint256 poolAllocationPercentMantissa,
        uint256 poolBalancerBlock,
        uint256 poolBalancePerDay,
        uint256 poolBalancePerMonth
    ) {
        uint256 poolBalancePerBlock = masterBalance.cakePerBlock() * masterBalance.BONUS_MULTIPLIER();
        ( lpToken, poolAllocationPoint,,) = masterBalance.getPoolInfo(pid);
        totalAllocationPoints = masterBalance.totalAllocPoint();
        poolAllocationPercentMantissa = (poolAllocationPoint.mul(1e18)).div(totalAllocationPoints);
        poolBalancePerBlock = (poolBalancePerBlock.mul(poolAllocationPercentMantissa)).div(1e18);
        // Assumes a 3 second blocktime
        poolBalancePerDay = poolBalancePerBlock * 1200 * 24;
        poolBalancePerMonth = poolBalancePerDay * 30;
    }

    /// @notice An external function to sweep accidental ERC20 transfers to this contract. 
    ///   Tokens are sent to owner
    /// @param _tokens Array of ERC20 addresses to sweep
    /// @param _to Address to send tokens to
    function sweepTokens(IERC20[] memory _tokens, address _to) external onlyOwner {
        for (uint256 index = 0; index < _tokens.length; index++) {
            IERC20 token = _tokens[index];
            uint256 balance = token.balanceOf(address(this));
            token.transfer(_to, balance);
            emit SweepWithdraw(_to, token, balance);
        }
    }

    /// @notice Transfer the farmAdmin to a new address
    /// @param _newFarmAdmin Address of new farmAdmin
    function transferFarmAdminOwnership(address _newFarmAdmin) external onlyFarmAdmin {
        require(_newFarmAdmin != address(0), 'cannot transfer farm admin to address(0)');
        address previousFarmAdmin = farmAdmin;
        farmAdmin = _newFarmAdmin;
        emit TransferredFarmAdmin(previousFarmAdmin, farmAdmin);
    }

    /// @notice Update pool allocations based on fixed percentage farm percentages
    function syncFixedPercentFarms() external onlyFarmAdmin {
        require(getNumberOfFixedPercentFarms() > 0, 'no fixed farms added');
        _syncFixedPercentFarms();
    }


    /// @notice Add a batch of farms to the MasterBalance contract
    /// @dev syncs fixed percentage farms after update
    /// @param _allocPoints Array of allocation points to set each address
    /// @param _withMassPoolUpdate Mass update pools before update
    /// @param _syncFixedPercentageFarms Sync fixed percentage farm allocations
    function addMasterBalanceFarms(
        uint256[] memory _allocPoints,
        IERC20[] memory _lpTokens,
        bool _withMassPoolUpdate,
        bool _syncFixedPercentageFarms
    ) external onlyFarmAdmin {
        require(_allocPoints.length == _lpTokens.length, "array length mismatch");

        if (_withMassPoolUpdate) {
            masterBalance.massUpdatePools();
        }

        for (uint256 index = 0; index < _allocPoints.length; index++) {
            masterBalance.add(_allocPoints[index], address(_lpTokens[index]), false);
            emit AddFarm(_lpTokens[index], _allocPoints[index]);
        }

        if (_syncFixedPercentageFarms) {
            _syncFixedPercentFarms();
        }
    }

    /// @notice Add a batch of farms to the MasterBalance contract
    /// @dev syncs fixed percentage farms after update
    /// @param _pids Array of MasterBalance pool ids to update
    /// @param _allocPoints Array of allocation points to set each pid
    /// @param _withMassPoolUpdate Mass update pools before update
    /// @param _syncFixedPercentageFarms Sync fixed percentage farm allocations
    function setMasterBalanceFarms(
        uint256[] memory _pids,
        uint256[] memory _allocPoints,
        bool _withMassPoolUpdate,
        bool _syncFixedPercentageFarms
    ) external onlyFarmAdmin {
        require(_pids.length == _allocPoints.length, "array length mismatch");

        if (_withMassPoolUpdate) {
            masterBalance.massUpdatePools();
        }

        uint256 pidIndexes = masterBalance.poolLength();
        for (uint256 index = 0; index < _pids.length; index++) {
            require(_pids[index] < pidIndexes, "pid is out of bounds of MasterBalance");
            // Set all pids with no update
            masterBalance.set(_pids[index], _allocPoints[index], false);
            emit SetFarm(_pids[index], _allocPoints[index]);
        }

        if (_syncFixedPercentageFarms) {
            _syncFixedPercentFarms();
        }
    }

    /// @notice Add a new fixed percentage farm allocation
    /// @dev Must be a new MasterBalance pid and below the max fixed percentage 
    /// @param _pid MasterBalance pid to create a fixed percentage farm for
    /// @param _allocPercentage Percentage based in PERCENTAGE_PRECISION
    /// @param _withMassPoolUpdate Mass update pools before update
    /// @param _syncFixedPercentageFarms Sync fixed percentage farm allocations
    function addFixedPercentFarmAllocation(
        uint256 _pid,
        uint256 _allocPercentage,
        bool _withMassPoolUpdate,
        bool _syncFixedPercentageFarms
    ) external onlyFarmAdmin {
        require(_pid < masterBalance.poolLength(), "pid is out of bounds of MasterBalance");
        require(_pid != 0, "cannot add reserved MasterBalance pid 0");
        require(!getFixedPercentFarmFromPid[_pid].isActive, "fixed percent farm already added");
        uint256 newTotalFixedPercentage = totalFixedPercentFarmPercentage.add(_allocPercentage);
        require(newTotalFixedPercentage <= MAX_FIXED_FARM_PERCENTAGE, "allocation out of bounds");
    
        totalFixedPercentFarmPercentage = newTotalFixedPercentage;
        getFixedPercentFarmFromPid[_pid] = FixedPercentFarmInfo(_pid, _allocPercentage, true);
        fixedPercentFarmPids.push(_pid);
        emit AddFixedPercentFarm(_pid, _allocPercentage);
       
        if (_withMassPoolUpdate) {
            masterBalance.massUpdatePools();
        }

        if (_syncFixedPercentageFarms) {
            _syncFixedPercentFarms();
        }
    }

    /// @notice Update/disable a new fixed percentage farm allocation
    /// @dev If the farm allocation is 0, then the fixed farm will be disabled, but the allocation will be unchanged.
    /// @param _pid MasterBalance pid linked to fixed percentage farm to update
    /// @param _allocPercentage Percentage based in PERCENTAGE_PRECISION
    /// @param _withMassPoolUpdate Mass update pools before update
    /// @param _syncFixedPercentageFarms Sync fixed percentage farm allocations
    function setFixedPercentFarmAllocation(
        uint256 _pid,
        uint256 _allocPercentage,
        bool _withMassPoolUpdate,
        bool _syncFixedPercentageFarms
    ) external onlyFarmAdmin {
        FixedPercentFarmInfo storage fixedPercentFarm = getFixedPercentFarmFromPid[_pid];
        require(fixedPercentFarm.isActive, "not a valid farm pid");
        uint256 newTotalFixedPercentFarmPercentage = _allocPercentage.add(totalFixedPercentFarmPercentage).sub(fixedPercentFarm.allocationPercent);
        require(newTotalFixedPercentFarmPercentage <= MAX_FIXED_FARM_PERCENTAGE, "new allocation out of bounds");

        totalFixedPercentFarmPercentage = newTotalFixedPercentFarmPercentage;
        uint256 previousAllocation = fixedPercentFarm.allocationPercent;
        fixedPercentFarm.allocationPercent = _allocPercentage;

        if(_allocPercentage == 0) {
            // Disable fixed percentage farm and MasterBalance allocation
            fixedPercentFarm.isActive = false;
            // Remove fixed percent farm from pid array
            for (uint256 index = 0; index < fixedPercentFarmPids.length; index++) {
                if(fixedPercentFarmPids[index] == _pid) {
                    _removeFromArray(index, fixedPercentFarmPids);
                    break;
                }
            }
            // NOTE: The MasterBalance pool allocation is left unchanged to not disable a fixed farm 
            //  in case the creation was an accident.
        }
        emit SetFixedPercentFarm(_pid, previousAllocation, _allocPercentage);
      
        if (_withMassPoolUpdate) {
            masterBalance.massUpdatePools();
        }

        if (_syncFixedPercentageFarms) {
            _syncFixedPercentFarms();
        }
    }

    /** Public Functions  */

    /// @notice Get the number of registered fixed percentage farms
    /// @return Number of active fixed percentage farms 
    function getNumberOfFixedPercentFarms() public view returns (uint256) {
        return fixedPercentFarmPids.length;
    }

    /// @notice Get the total percentage allocated to fixed percentage farms on the MasterBalance
    /// @dev Adds the total percent allocated to fixed percentage farms with the percentage allocated to the Balance pool. 
    ///  The MasterBalance manages the Balance pool internally and we need to account for this when syncing fixed percentage farms.
    /// @return Total percentage based in PERCENTAGE_PRECISION 
    function getTotalAllocationPercent() public view returns (uint256) {
        return totalFixedPercentFarmPercentage + BASE_PERCENTAGE;
    }


    /** Internal Functions  */

    /// @notice Run through fixed percentage farm allocations and set MasterBalance allocations to match the percentage.
    /// @dev The MasterBalance contract manages the Balance pool percentage on its own which is accounted for in the calculations below. 
    function _syncFixedPercentFarms() internal {
        uint256 numberOfFixedPercentFarms = getNumberOfFixedPercentFarms();
        if(numberOfFixedPercentFarms == 0) {
            return; 
        }
        uint256 masterBalanceTotalAllocation = masterBalance.totalAllocPoint();
        ( ,uint256 poolAllocation,,) = masterBalance.getPoolInfo(0);
        uint256 currentTotalFixedPercentFarmAllocation = 0;
        // Define local vars that are used multiple times
        uint256 totalAllocationPercent = getTotalAllocationPercent();
        // Calculate the total allocation points of the fixed percent farms
        for (uint256 index = 0; index < numberOfFixedPercentFarms; index++) {
            ( ,uint256 fixedPercentFarmAllocation,,) = masterBalance.getPoolInfo(fixedPercentFarmPids[index]);
            currentTotalFixedPercentFarmAllocation = currentTotalFixedPercentFarmAllocation.add(fixedPercentFarmAllocation);
        }
        // Calculate alloted allocations
        uint256 nonPercentageBasedAllocation = masterBalanceTotalAllocation.sub(poolAllocation).sub(currentTotalFixedPercentFarmAllocation);
        uint256 percentageIncrease = (PERCENTAGE_PRECISION * PERCENTAGE_PRECISION) / (PERCENTAGE_PRECISION.sub(totalAllocationPercent));
        uint256 finalAllocation = nonPercentageBasedAllocation.mul(percentageIncrease).div(PERCENTAGE_PRECISION);
        uint256 allotedFixedPercentFarmAllocation = finalAllocation.sub(nonPercentageBasedAllocation);
        // Update fixed percentage farm allocations
        for (uint256 index = 0; index < numberOfFixedPercentFarms; index++) {
            FixedPercentFarmInfo memory fixedPercentFarm = getFixedPercentFarmFromPid[fixedPercentFarmPids[index]];
            uint256 newFixedPercentFarmAllocation = allotedFixedPercentFarmAllocation.mul(fixedPercentFarm.allocationPercent).div(totalAllocationPercent);
            masterBalance.set(fixedPercentFarm.pid, newFixedPercentFarmAllocation, false);
            emit SyncFixedPercentFarm(fixedPercentFarm.pid, newFixedPercentFarmAllocation);
        }
    }

    /// @notice Remove an index from an array by copying the last element to the index and then removing the last element.
    function _removeFromArray(uint index, uint256[] storage array) internal {
        require(index < array.length, "Incorrect index");
        array[index] = array[array.length-1];
        array.pop();
    }
}
