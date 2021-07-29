import { ethers } from 'hardhat';

const ChiManager = '0x5E33e65447806eef15dB6FF52917082c3D4FBf56';

async function main() {
    const CHIDeployerFactory = await ethers.getContractFactory('CHIVaultDeployer');
    const CHIDeployer = await CHIDeployerFactory.deploy();
    await CHIDeployer.deployed();

    const CHIManagerFactory = await ethers.getContractFactory('CHIManager');
    const CHIManager = await CHIManagerFactory.attach(ChiManager)

    console.log('CHIVaultDeployer:')
    console.log(CHIDeployer.address) // 0x3Fe90e5e7c036fC8BB3beBdA884F4F7Fb9dF86bC 
    console.log(CHIDeployer.deployTransaction.hash);

    await CHIManager.setDeployer(CHIDeployer.address)
    await CHIDeployer.setCHIManager(CHIManager.address)
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
