import { ethers } from 'hardhat';

const YangNFT = '0xb07F3328b4746969113CF5369e138eD6d42Aa47e';
const MerkleRoot = '0xdb45131226a82a3ac77bac89d823bed43d130e9cb50cd0f03c84f6d28264a78f';
const UniV3Factory = '0x1F98431c8aD98523631AE4a59f267346ea31F984';


async function main() {
    const CHIDeployerFactory = await ethers.getContractFactory('CHIVaultDeployer');
    const CHIManagerFactory = await ethers.getContractFactory('CHIManager');
    const CHIDeployer = await CHIDeployerFactory.deploy();
    await CHIDeployer.deployed();

    const CHIManager = await CHIManagerFactory.deploy(
        UniV3Factory,
        YangNFT,
        CHIDeployer.address,
        MerkleRoot
    );
    await CHIManager.deployed();

    console.log('CHIVaultDeployer:')
    console.log(CHIDeployer.address) // 0x16bf35e466caf176550A6E29c003C047956C77F2
    console.log(CHIDeployer.deployTransaction.hash);

    console.log('CHIManager')
    console.log(CHIManager.address) // 0x0f2EC6511E69A3b7Aa117920275768b951D868Ca
    console.log(CHIManager.deployTransaction.hash);

    await CHIDeployer.setCHIManager(CHIManager.address)
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
