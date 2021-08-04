import { ethers } from 'hardhat';

const ChiManager = '0x4f60d5217531a00947cc3592e76A8a01dea7BD2C';

async function main() {
    const CHIDeployerFactory = await ethers.getContractFactory('CHIVaultDeployer');
    const CHIDeployer = await CHIDeployerFactory.deploy();
    await CHIDeployer.deployed();

    const CHIManagerFactory = await ethers.getContractFactory('CHIManager');
    const CHIManager = await CHIManagerFactory.attach(ChiManager)

    console.log('CHIVaultDeployer:')
    //0x17051178f8F43e7d715A94ECf42fD690bf96311D
    //0x4318d8f0494760f3683801e5945166611ac477fa447d6de65633226cb306e87e
    console.log(CHIDeployer.address)
    console.log(CHIDeployer.deployTransaction.hash);

    await CHIManager.updateDeployer(CHIDeployer.address)
    await CHIDeployer.setCHIManager(CHIManager.address)
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
