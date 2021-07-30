const { ethers, upgrades } = require('hardhat');

const RewardPoolAddr = '0xF5e3e76Da5423BafD8764FB5aF0AaC7398a8574C'

async function main() {
    const factory = await ethers.getContractFactory('RewardPool');
    const rewardPool = await upgrades.upgradeProxy(RewardPoolAddr, factory);
    console.log('Upgrade RewardPool')
    console.log(rewardPool.address)
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });

