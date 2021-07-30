const { ethers, upgrades } = require('hardhat');

const RewardPoolAddr = '0x9AF53485b8BC4Ff807CF1F5564c55fE12F019c96'

async function main() {
    const factory = await ethers.getContractFactory('RewardPool');
    const rewardPool = await upgrades.upgradeProxy(RewardPoolAddr, factory);
    console.log('Upgrade RewardPool') // 0x9AF53485b8BC4Ff807CF1F5564c55fE12F019c96
    console.log(rewardPool.address)
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });

