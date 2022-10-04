const { getNetworkConfig } = require('../deploy-config')
const MasterBalanceAdmin = artifacts.require("MasterBalanceAdmin");

module.exports = async function(deployer, network, accounts) {
    const { masterBalanceAddress, masterBalanceAdminOwner, farmAdmin} = getNetworkConfig(network, accounts);

    await deployer.deploy(MasterBalanceAdmin, masterBalanceAddress, farmAdmin);
    const masterBalanceAdmin = await MasterBalanceAdmin.at(MasterBalanceAdmin.address);
    await masterBalanceAdmin.transferOwnership(masterBalanceAdminOwner);

    const currentMasterBalanceAdminOwner = await masterBalanceAdmin.owner();
    const currentFarmAdmin = await masterBalanceAdmin.farmAdmin();

    console.dir({
      MasterBalanceAdminContract: masterBalanceAdmin.address,
      currentMasterBalanceAdminOwner,
      currentFarmAdmin,
    });
};