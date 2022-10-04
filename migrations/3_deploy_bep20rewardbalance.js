const BEP20RewardBalanceV2 = artifacts.require("BEP20RewardBalanceV2");


const deployConfigs = [
    // {
    //   name: " Reward Pool",
    //   stakeToken: '', // token
    //   rewardToken: '', // num token
    //   rewardPerBlock: '', // x_token / Block (x decimals) x Blocks total
    //   startBlock: '', // x_date x_time UTC
    //   bonusEndBlock: '' // x Months
    // },
    {
      name: " Balance -> BUSD Reward Pool",
      stakeToken: '0x78867BbEeF44f2326bF8DDd1941a4439382EF2A7', //BLN
      rewardToken: '0xA370216CC1e92c654193A6a6Ecd7EBdbF9FEeC3e', // BUSD // 0xA370216CC1e92c654193A6a6Ecd7EBdbF9FEeC3e
      rewardPerBlock: '2474537037000000', // 0.002474537037 / Block (18 decimals)
      startBlock: '21777379', // x_date x_time UTC
      bonusEndBlock: '22641379' // 30 Days / 864000 Blocks
    },
  ]
  
// let block = await web3.eth.getBlock("latest")
module.exports = async function(deployer, network, accounts) {
    // mainnet
    const adminAddress = '0x27301b4470673BeAbb8d25b24CCe12AB77D088e5';

    const BLOCKS_PER_DAY = 28800;
    const BLOCK_DURATION = BLOCKS_PER_DAY * 7

    let deployLogs = [];

    for (const deployConfig of deployConfigs) {
        const { name, stakeToken, rewardToken, rewardPerBlock, startBlock, bonusEndBlock } = deployConfig;
    
        console.log("Deploying BEP20RewardBalance with config:");
        console.dir(deployConfig);
    
        await deployer.deploy(BEP20RewardBalanceV2, stakeToken, rewardToken, rewardPerBlock, startBlock, bonusEndBlock);
        const BEP20RewardBalanceV2 = await BEP20RewardBalanceV2.deployed();
        await BEP20RewardBalanceV2.transferOwnership(adminAddress);

        deployLogs.push({
            name,
            address: BEP20RewardBalanceV2.address,
            stakeToken,
            rewardToken,
            rewardPerBlock,
            startBlock,
            bonusEndBlock
        });
      }

    console.log(JSON.stringify(deployLogs));
};