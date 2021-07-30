const { ethers, upgrades } = require('hardhat');

const rewardToken = '0x684582ab5e52a194c0c9311a7a1cd991b0081518' // YIN
const chiManager = '0x4f60d5217531a00947cc3592e76A8a01dea7BD2C'
const yangNFT = '0x24998A77e60660757B353fEA0A5F39C21a027c9B'
const duration = 3600 * 24 * 365 // a year

async function main () {
    const factory = await ethers.getContractFactory('RewardPool');

    const rewardPool = await upgrades.deployProxy(factory, [rewardToken, chiManager, yangNFT, duration]);
    await rewardPool.deployed();

    console.log('rewardPool')
    console.log(rewardPool.address)
    console.log(rewardPool.deployTransaction.hash);
}

main()

/*
0.
0x9AF53485b8BC4Ff807CF1F5564c55fE12F019c96
0x826241a1c007e453c406d68812b1258cd085538a93e9c1967bb0d16f20579f6e

1.
0x035cC163aD4EBBc6272D95eb0Fa64677e0fd70f8
0x3d67ae288a846e369ae038de297936b1455228424808f68e54cb887c288bea21
*/
