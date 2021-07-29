const { ethers, upgrades } = require('hardhat');

const YangNFT = '0x24998A77e60660757B353fEA0A5F39C21a027c9B';
const MerkleRoot = '0xdb45131226a82a3ac77bac89d823bed43d130e9cb50cd0f03c84f6d28264a78f';
const UniV3Factory = '0x1F98431c8aD98523631AE4a59f267346ea31F984';
const InitId = 1;
const VaultFee = 70000;
const Manager = '0x5a0350846f321524d0fBe0C6A94027E89bE23bE5';

async function main () {
    const CHIDeployerFactory = await ethers.getContractFactory('CHIVaultDeployer');
    const CHIManagerFactory = await ethers.getContractFactory('CHIManager');
    const CHIDeployer = await CHIDeployerFactory.deploy();
    await CHIDeployer.deployed();

    const CHIManager = await upgrades.deployProxy(
        CHIManagerFactory,
        [
            MerkleRoot,
            InitId,
            VaultFee,
            UniV3Factory,
            YangNFT,
            CHIDeployer.address,
            Manager
        ]);
    await CHIManager.deployed();

    console.log('CHIVaultDeployer:')
    console.log(CHIDeployer.address) // 0xFCBe3Bd5255bdDBD5616FF74Ed502A128fbBf310
    console.log(CHIDeployer.deployTransaction.hash); // 0x2200fe3c56891e7c2c1c218d76067c4e7096b7808af13b0c6433e65fde28c4bd

    console.log('CHIManager')
    console.log(CHIManager.address) // 0x4f60d5217531a00947cc3592e76A8a01dea7BD2C
    console.log(CHIManager.deployTransaction.hash); // 0x0cbe7c11a815b382f5fcec65a11b0b23480041a4ba98c77c55f748eee3f77492

    await CHIDeployer.setCHIManager(CHIManager.address)
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });

