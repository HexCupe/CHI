const { ethers, upgrades } = require('hardhat');

const CHIManagerAddr = '0x5E33e65447806eef15dB6FF52917082c3D4FBf56'

async function main() {
    const CHIFactory = await ethers.getContractFactory('CHIManager');
    const CHIManager = await upgrades.upgradeProxy(CHIManagerAddr, CHIFactory);
    console.log('Upgrade CHIManager') // 0x5E33e65447806eef15dB6FF52917082c3D4FBf56
    console.log(CHIManager.address)
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
