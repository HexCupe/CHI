const { ethers, upgrades } = require('hardhat');

const RewardPoolAddr = '0x035cC163aD4EBBc6272D95eb0Fa64677e0fd70f8'

async function main() {
    const factory = await ethers.getContractFactory('RewardPool');
    const rewardPool = await upgrades.upgradeProxy(RewardPoolAddr, factory);
    console.log('Upgrade RewardPool') // 0x035cC163aD4EBBc6272D95eb0Fa64677e0fd70f8
    console.log(rewardPool.address)
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });

