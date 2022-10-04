
function getNetworkConfig(network, accounts) {
    if(["bsc", "bsc-fork"].includes(network)) {
        console.log(`Deploying with BSC MAINNET config.`)
        return {
            adminAddress: '0xb58967989C8e878de4D7e78965e066F26B2d9bF4', // General Admin
            feeAccount: "", // Proxy Admin
            masterApeAddress:"" , // Production
            // masterBalanceAddress: "", // Dummy
            masterBalanceAdminOwner:"" , // OZ Timelock Beta
            farmAdmin: '0xb58967989C8e878de4D7e78965e066F26B2d9bF4', // OZ Timelock Alpha
            STARTING_BLOCK: 4853714,
            TOKENS_PER_BLOCK: 10,
            TIMELOCK_DELAY_SECS: 3600 * 6,
            INITIAL_MINT: '25000',
        }
    } else if (['testnet', 'bsc-testnet-fork'].includes(network)) {
        console.log(`Deploying with BSC testnet config.`)
        return {
            adminAddress: '0xb58967989C8e878de4D7e78965e066F26B2d9bF4', // General Admin
            feeAccount: '0xb58967989C8e878de4D7e78965e066F26B2d9bF4', // Proxy Admin
            masterBalanceAddress: '0x',
            masterBalanceAdminOwner: '0xb58967989C8e878de4D7e78965e066F26B2d9bF4', 
            farmAdmin: '0x',
            STARTING_BLOCK: 12338486,
            TOKENS_PER_BLOCK: 10,
            TIMELOCK_DELAY_SECS: 3600 * 6,
            INITIAL_MINT: '25000',
            masterBalanceAddress: '0x', 
        }
    } else if (['development'].includes(network)) {
        console.log(`Deploying with development config.`)
        return {
            adminAddress: "", // General Admin
            feeAccount: "", // Proxy Admin
            masterBalanceAddress: '0x',
            masterBalanceAdminOwner: '0x',
            farmAdmin: '0x',
            STARTING_BLOCK: 0,
            TOKENS_PER_BLOCK: 10,
            TIMELOCK_DELAY_SECS: 3600 * 6,
            INITIAL_MINT: '25000',
        }
    } else {
        throw new Error(`No config found for network ${network}.`)
    }
}

module.exports = { getNetworkConfig };
