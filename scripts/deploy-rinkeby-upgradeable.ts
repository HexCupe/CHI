const { ethers, upgrades } = require('hardhat');

const YangNFT = '0x0de96Fc05F16105077550c26407Fb78164345851';
const MerkleRoot = '0xdb45131226a82a3ac77bac89d823bed43d130e9cb50cd0f03c84f6d28264a78f';
const UniV3Factory = '0x1F98431c8aD98523631AE4a59f267346ea31F984';
const InitId = 1;

async function main () {
    const CHIDeployerFactory = await ethers.getContractFactory('CHIVaultDeployer');
    const CHIManagerFactory = await ethers.getContractFactory('CHIManager');
    const CHIDeployer = await CHIDeployerFactory.deploy();
    await CHIDeployer.deployed();

    const CHIManager = await upgrades.deployProxy(
        CHIManagerFactory, [InitId, UniV3Factory, YangNFT, CHIDeployer.address, MerkleRoot]);
    await CHIManager.deployed();

    console.log('CHIVaultDeployer:')
    console.log(CHIDeployer.address) // 0x283e50f4032d8D7A9601e42714C42F2A005704fD
    console.log(CHIDeployer.deployTransaction.hash);

    console.log('CHIManager')
    console.log(CHIManager.address) // 0x5E33e65447806eef15dB6FF52917082c3D4FBf56
    console.log(CHIManager.deployTransaction.hash);

    await CHIDeployer.setCHIManager(CHIManager.address)
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });

