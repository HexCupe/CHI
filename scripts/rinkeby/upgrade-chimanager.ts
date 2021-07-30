const { ethers, upgrades } = require('hardhat');

const CHIManagerAddr = '0x4f60d5217531a00947cc3592e76A8a01dea7BD2C'

async function main() {
    const CHIFactory = await ethers.getContractFactory('CHIManager');
    const CHIManager = await upgrades.upgradeProxy(CHIManagerAddr, CHIFactory);
    console.log('Upgrade CHIManager') // 0x4f60d5217531a00947cc3592e76A8a01dea7BD2C
    console.log(CHIManager.address)
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
