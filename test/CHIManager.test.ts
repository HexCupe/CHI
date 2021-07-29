import { BigNumber, constants, Wallet } from 'ethers'
import { ethers, waffle } from 'hardhat'
import { expect } from './common/expect'
import { allFixture, AllFixture } from './common/allFixture'
import { FeeAmount, TICK_SPACINGS, ZeroAddress, MaxUint128, MIN_SQRT_RATIO, MAX_SQRT_RATIO } from './common/constants'
import { USDCAddress, USDTAddress } from './common/address'
import { convertTo18Decimals, getMinTick, getMaxTick, getPositionKey } from './common/utilities'
import { IUniswapV3Factory } from '../typechain/IUniswapV3Factory'
import { IUniswapV3Pool } from '../typechain/IUniswapV3Pool'
import { MockERC20, MockYANG, CHIVaultDeployer, CHIVault, CHIManager, MockRouter } from '../typechain'
import { encodePriceSqrt } from './common/encodePriceSqrt'
import WhiteListTree from './common/whitelist-tree'

describe('CHIManager', () => {
  const wallets = waffle.provider.getWallets()
  const [gov, other] = wallets
  const tree = new WhiteListTree([gov.address])

  let loadFixture: ReturnType<typeof waffle.createFixtureLoader>

  let yang: MockYANG
  let token0: MockERC20, token1: MockERC20, token2: MockERC20
  let chiVaultDeployer: CHIVaultDeployer
  let chiManager: CHIManager
  let uniswapV3Factory: IUniswapV3Factory
  let router: MockRouter
  let ctx: AllFixture

  const vaultFee = 7 * 1e4

  before('create fixture loader', async () => {
    loadFixture = waffle.createFixtureLoader(wallets)
  })
  beforeEach('load fixture', async () => {
    ctx = await loadFixture(allFixture)
    yang = ctx.yang
    token0 = ctx.token0
    token1 = ctx.token1
    token2 = ctx.token2
    chiManager = ctx.chi
    chiVaultDeployer = ctx.chiVaultDeployer
    router = ctx.router
    uniswapV3Factory = ctx.uniswapV3Factory
  })

  async function mint(
    recipient: string,
    token0: string,
    token1: string,
    fee: number,
    proof: string[],
    caller: Wallet = gov
  ): Promise<{
    tokenId: number
    vault: string
  }> {
    const mintParams = {
      recipient,
      token0,
      token1,
      fee,
    }

    const { tokenId, vault } = await chiManager.connect(caller).callStatic.mint(mintParams, proof)
    await chiManager.connect(caller).mint(mintParams, proof)
    return {
      tokenId: tokenId.toNumber(),
      vault,
    }
  }
  describe('Mint CHI NFT', async () => {
    describe('success cases', () => {
      it('succeeds for mint', async () => {
        // non-existent v3 pool
        const proof = tree.getHexProof(gov.address)
        await expect(mint(gov.address, token0.address, token1.address, FeeAmount.MEDIUM, proof)).to.be.revertedWith(
          'Non-existent pool'
        )
        //// more than FEE_BASE
        //await expect(mint(gov.address, USDCAddress, USDTAddress, FeeAmount.MEDIUM, 1e6, proof)).to.be.revertedWith('f')

        const { tokenId: tokenId1 } = await mint(gov.address, USDCAddress, USDTAddress, FeeAmount.MEDIUM, proof)
        expect(gov.address).to.eq(await chiManager.ownerOf(tokenId1))

        expect(await chiManager.balanceOf(gov.address)).to.eq(1)

        const { tokenId: tokenId2, vault: vaultAddress } = await mint(
          gov.address,
          USDCAddress,
          USDTAddress,
          FeeAmount.MEDIUM,
          proof
        )
        expect(tokenId2).to.eq(tokenId1 + 1)
        expect(gov.address).to.eq(await chiManager.ownerOf(tokenId2))

        expect(await chiManager.balanceOf(gov.address)).to.eq(2)

        const chiInfo = await chiManager.chi(tokenId2)
        expect(chiInfo.owner).to.eq(gov.address)
        expect(chiInfo.operator).to.eq(gov.address)
        expect(chiInfo.pool).to.eq(await uniswapV3Factory.getPool(USDCAddress, USDTAddress, FeeAmount.MEDIUM))
        expect(chiInfo.vault).to.eq(vaultAddress)
        expect(chiInfo.accruedProtocolFees0).to.eq(0)
        expect(chiInfo.accruedProtocolFees1).to.eq(0)
        expect(chiInfo.fee).to.eq(vaultFee)
        expect(chiInfo.totalShares).to.eq(0)
      })

      it('succeeds for approve a operator', async () => {
        const proof = tree.getHexProof(gov.address);
        const { tokenId: tokenId1 } = await mint(gov.address, USDCAddress, USDTAddress, FeeAmount.MEDIUM, proof)
        expect(gov.address).to.eq(await chiManager.ownerOf(tokenId1))

        let chi1 = await chiManager.chi(tokenId1)

        expect(chi1.owner).to.eq(gov.address)
        expect(chi1.operator).to.eq(gov.address)

        await chiManager.approve(other.address, tokenId1)

        chi1 = await chiManager.chi(tokenId1)
        expect(chi1.owner).to.eq(gov.address)
        expect(chi1.operator).to.eq(other.address)

        const operator = await chiManager.getApproved(tokenId1)
        expect(operator).to.eq(other.address)
      })
    })
    describe('fails cases', () => {
      it('fails if minter is not a gov', async () => {
        const proof = tree.getHexProof(gov.address)
        await expect(
          mint(gov.address, token0.address, token1.address, FeeAmount.MEDIUM, proof, wallets[1])
        ).to.be.revertedWith('gov')
      })
    })
  })

  describe('Manage CHI', async () => {
    const tokenAmount0 = convertTo18Decimals(10000)
    const tokenAmount1 = convertTo18Decimals(10000)
    const startingTick = 0
    const feeAmount = FeeAmount.MEDIUM
    const tickSpacing = TICK_SPACINGS[feeAmount]
    const minTick = getMinTick(tickSpacing)
    const maxTick = getMaxTick(tickSpacing)
    let uniswapV3Pool: IUniswapV3Pool
    let chivault: CHIVault
    let tokenId1: number
    // set inital price
    // set 1:1
    const initPrice = encodePriceSqrt(1, 1)
    beforeEach('Mint CHI', async () => {
      const poolAddress = await uniswapV3Factory.callStatic.createPool(token0.address, token1.address, FeeAmount.MEDIUM)
      await uniswapV3Factory.createPool(token0.address, token1.address, FeeAmount.MEDIUM)

      // add liquidity
      await token0.approve(router.address, constants.MaxUint256)
      await token1.approve(router.address, constants.MaxUint256)

      uniswapV3Pool = (await ethers.getContractAt('IUniswapV3Pool', poolAddress)) as IUniswapV3Pool

      await uniswapV3Pool.initialize(initPrice)

      expect((await uniswapV3Pool.slot0()).tick).to.eq(startingTick)
      expect((await uniswapV3Pool.slot0()).sqrtPriceX96).to.eq(initPrice)
      // wait for manager test
      await router.mint(poolAddress, minTick, maxTick, convertTo18Decimals(1))

      const proof = tree.getHexProof(gov.address)
      const { tokenId, vault } = await mint(gov.address, token0.address, token1.address, FeeAmount.MEDIUM, proof)
      tokenId1 = tokenId
      chivault = (await ethers.getContractAt('CHIVault', vault)) as CHIVault
      // deposit to YANG
      await token0.approve(yang.address, MaxUint128)
      await token1.approve(yang.address, MaxUint128)

      await yang.deposit(token0.address, tokenAmount0, token1.address, tokenAmount1)
    })
    describe('success cases', () => {
      it('add and remove range', async () => {
        await chiManager.addRange(tokenId1, minTick, maxTick)
        expect(await chivault.getRangeCount()).to.eq(1)
        const ticks01 = await chivault.getRange(0)
        expect(ticks01.tickLower).to.eq(minTick)
        expect(ticks01.tickUpper).to.eq(maxTick)

        // add the same tick
        await chiManager.addRange(tokenId1, minTick, maxTick)
        expect(await chivault.getRangeCount()).to.eq(1)
        const ticks02 = await chivault.getRange(0)
        expect(ticks02.tickLower).to.eq(minTick)
        expect(ticks02.tickUpper).to.eq(maxTick)

        await chiManager.removeRange(tokenId1, minTick, maxTick)
        expect(await chivault.getRangeCount()).to.eq(0)
      })

      it('addAndRemoveRanges', async () => {
        const addParams = [
          {
            tickLower: minTick,
            tickUpper: maxTick,
          },
          {
            tickLower: 5 * tickSpacing,
            tickUpper: 10 * tickSpacing,
          },
        ]

        await chiManager.addAndRemoveRanges(tokenId1, addParams, [])
        expect(await chivault.getRangeCount()).to.eq(2)
        const ticks01 = await chivault.getRange(0)
        expect(ticks01.tickLower).to.eq(minTick)
        expect(ticks01.tickUpper).to.eq(maxTick)

        const ticks02 = await chivault.getRange(1)
        expect(ticks02.tickLower).to.eq(5 * tickSpacing)
        expect(ticks02.tickUpper).to.eq(10 * tickSpacing)

        const addParams02 = [
          {
            tickLower: 10 * tickSpacing,
            tickUpper: 50 * tickSpacing,
          },
        ]
        // add and remove
        await chiManager.addAndRemoveRanges(tokenId1, addParams02, addParams)
        expect(await chivault.getRangeCount()).to.eq(1)
        const ticks03 = await chivault.getRange(0)
        expect(ticks03.tickLower).to.eq(10 * tickSpacing)
        expect(ticks03.tickUpper).to.eq(50 * tickSpacing)
      })
      it('subscribe and unsubscribe', async () => {
        expect(await yang.totallyShares()).to.eq(0)
        expect(await token0.balanceOf(yang.address)).to.eq(tokenAmount0)
        expect(await token1.balanceOf(yang.address)).to.eq(tokenAmount1)
        const subscribeParam = {
          yangId: 1,
          chiId: tokenId1,
          amount0Desired: convertTo18Decimals(1000),
          amount1Desired: convertTo18Decimals(1000),
          amount0Min: 0,
          amount1Min: 0,
        }
        await yang.subscribe(subscribeParam)
        expect(await yang.totallyShares()).to.eq(convertTo18Decimals(1000))
        expect(await token0.balanceOf(yang.address)).to.eq(convertTo18Decimals(9000))
        expect(await token1.balanceOf(yang.address)).to.eq(convertTo18Decimals(9000))

        const unsubscribeParam = {
          yangId: 1,
          chiId: tokenId1,
          shares: await yang.totallyShares(),
          amount0Min: convertTo18Decimals(1000),
          amount1Min: convertTo18Decimals(1000),
        }
        await yang.unsubscribe(unsubscribeParam)
        expect(await yang.totallyShares()).to.eq(0)
        expect(await token0.balanceOf(yang.address)).to.eq(convertTo18Decimals(10000))
        expect(await token1.balanceOf(yang.address)).to.eq(convertTo18Decimals(10000))
      })

      it('add liquidity and remove liquidity', async () => {
        const subscribeParam = {
          yangId: 1,
          chiId: tokenId1,
          amount0Desired: convertTo18Decimals(1000),
          amount1Desired: convertTo18Decimals(1000),
          amount0Min: 0,
          amount1Min: 0,
        }
        await yang.subscribe(subscribeParam)
        expect(await token0.balanceOf(yang.address)).to.eq(convertTo18Decimals(9000))
        expect(await token1.balanceOf(yang.address)).to.eq(convertTo18Decimals(9000))
        // let token0 and token1 in all tick
        // means it should be 1:1
        await chiManager.addRange(tokenId1, minTick, maxTick)
        await chiManager.addLiquidityToPosition(tokenId1, 0, convertTo18Decimals(1000), convertTo18Decimals(1000))
        expect(await token0.balanceOf(await chivault.pool())).to.eq(convertTo18Decimals(1001))
        expect(await token1.balanceOf(await chivault.pool())).to.eq(convertTo18Decimals(1001))

        await yang.subscribe(subscribeParam)
        expect(await token0.balanceOf(yang.address)).to.eq(convertTo18Decimals(8000))
        expect(await token1.balanceOf(yang.address)).to.eq(convertTo18Decimals(8000))
        await chiManager.addLiquidityToPosition(tokenId1, 0, convertTo18Decimals(1000), convertTo18Decimals(1000))

        expect(await token0.balanceOf(await chivault.pool())).to.eq(convertTo18Decimals(2001))
        expect(await token1.balanceOf(await chivault.pool())).to.eq(convertTo18Decimals(2001))

        await chiManager.removeAllLiquidityFromPosition(tokenId1, 0)
        // hmm.. some leave in pool
        expect(await token0.balanceOf(await chivault.pool())).to.eq(convertTo18Decimals(1).add(1))
        expect(await token1.balanceOf(await chivault.pool())).to.eq(convertTo18Decimals(1).add(1))
      })

      it('withdraw unused first when remove liquidity', async () => {
        const subscribeParam0 = {
          yangId: 1,
          chiId: tokenId1,
          amount0Desired: convertTo18Decimals(1000),
          amount1Desired: convertTo18Decimals(1000),
          amount0Min: 0,
          amount1Min: 0,
        }
        await yang.subscribe(subscribeParam0)
        expect(await token0.balanceOf(yang.address)).to.eq(convertTo18Decimals(9000))
        expect(await token1.balanceOf(yang.address)).to.eq(convertTo18Decimals(9000))
        // let token0 and token1 in all tick
        // means it should be 1:1
        await chiManager.addRange(tokenId1, minTick, maxTick)
        await chiManager.addLiquidityToPosition(tokenId1, 0, convertTo18Decimals(1000), convertTo18Decimals(1000))
        expect(await token0.balanceOf(await chivault.pool())).to.eq(convertTo18Decimals(1001))
        expect(await token1.balanceOf(await chivault.pool())).to.eq(convertTo18Decimals(1001))

        // big subscribe
        const subscribeParam1 = {
          yangId: 1,
          chiId: tokenId1,
          amount0Desired: convertTo18Decimals(9000),
          amount1Desired: convertTo18Decimals(9000),
          amount0Min: 0,
          amount1Min: 0,
        }
        await yang.subscribe(subscribeParam1)
        expect(await token0.balanceOf(yang.address)).to.eq(convertTo18Decimals(0))
        expect(await token1.balanceOf(yang.address)).to.eq(convertTo18Decimals(0))
        await chiManager.addLiquidityToPosition(tokenId1, 0, convertTo18Decimals(9000), convertTo18Decimals(9000))

        expect(await token0.balanceOf(await chivault.pool())).to.eq(convertTo18Decimals(10001))
        expect(await token1.balanceOf(await chivault.pool())).to.eq(convertTo18Decimals(10001))

        // withdrawal 90%
        const totalShares = await chivault.totalSupply()
        const withdrawShares = (await yang.totallyShares()).mul(90).div(100)
        const unsubscribeParam = {
          yangId: 1,
          chiId: tokenId1,
          shares: withdrawShares,
          amount0Min: convertTo18Decimals(9000).mul(withdrawShares).div(totalShares),
          amount1Min: convertTo18Decimals(9000).mul(withdrawShares).div(totalShares),
        }
        await yang.unsubscribe(unsubscribeParam)

        const [total0, total1] = await chivault.getTotalAmounts()
        const [lquidityTotal0, lquidityTotal1] = await chivault.getTotalLiquidityAmounts()
        // utils rate should more then 99.9%
        expect(lquidityTotal0.mul(1e6).div(total0)).to.be.gte(99900)
        expect(lquidityTotal1.mul(1e6).div(total1)).to.be.gte(99900)
      })

      it('swap and calculate fee', async () => {
        const subscribeParam = {
          yangId: 1,
          chiId: tokenId1,
          amount0Desired: convertTo18Decimals(1000),
          amount1Desired: convertTo18Decimals(1000),
          amount0Min: 0,
          amount1Min: 0,
        }
        await yang.subscribe(subscribeParam)
        await chiManager.addRange(tokenId1, minTick, maxTick)
        await chiManager.addLiquidityToPosition(tokenId1, 0, convertTo18Decimals(1000), convertTo18Decimals(1000))
        expect(await token0.balanceOf(await chivault.pool())).to.eq(convertTo18Decimals(1001))
        expect(await token1.balanceOf(await chivault.pool())).to.eq(convertTo18Decimals(1001))
        const { amount0Delta, amount1Delta, nextSqrtRatio } = await router.callStatic.getSwapResult(
          await chivault.pool(),
          true,
          convertTo18Decimals(1),
          MIN_SQRT_RATIO.add(1)
        )
        await router.getSwapResult(await chivault.pool(), true, convertTo18Decimals(1), MIN_SQRT_RATIO.add(1))
        expect(await token0.balanceOf(await chivault.pool())).to.eq(convertTo18Decimals(1001).add(amount0Delta))
        expect(await token1.balanceOf(await chivault.pool())).to.eq(convertTo18Decimals(1001).add(amount1Delta))

        await chivault.harvestFee()
        // v3 fee 0.3% and protocol fee 7%
        expect(await chivault.accruedProtocolFees0()).be.eq(
          convertTo18Decimals(1)
            .mul(3)
            .div(1000)
            .mul(vaultFee)
            .div(1e6)
            .mul(convertTo18Decimals(1000))
            .div(convertTo18Decimals(1001))
        )
        expect(await chivault.accruedProtocolFees1()).be.eq(0)
      })
      it('swap and remove liquidity', async () => {
        const subscribeParam = {
          yangId: 1,
          chiId: tokenId1,
          amount0Desired: convertTo18Decimals(1000),
          amount1Desired: convertTo18Decimals(1000),
          amount0Min: 0,
          amount1Min: 0,
        }
        await yang.subscribe(subscribeParam)
        await chiManager.addRange(tokenId1, minTick, maxTick)
        await chiManager.addLiquidityToPosition(tokenId1, 0, convertTo18Decimals(1000), convertTo18Decimals(1000))
        const { amount0Delta, amount1Delta, nextSqrtRatio } = await router.callStatic.getSwapResult(
          await chivault.pool(),
          true,
          convertTo18Decimals(1),
          MIN_SQRT_RATIO.add(1)
        )
        await router.getSwapResult(await chivault.pool(), true, convertTo18Decimals(1), MIN_SQRT_RATIO.add(1))
        await chivault.harvestFee()
        const unsubscribeParam = {
          yangId: 1,
          chiId: tokenId1,
          shares: await yang.totallyShares(),
          amount0Min: 0,
          amount1Min: 0,
        }
        await yang.unsubscribe(unsubscribeParam)
        // 209790209790209 is protocol fee
        expect(await token0.balanceOf(yang.address)).to.eq(
          tokenAmount0
            .add(amount0Delta.mul(convertTo18Decimals(1000)).div(convertTo18Decimals(1001)))
            .sub(209790209790209)
        )
        expect(await token1.balanceOf(yang.address)).to.eq(
          tokenAmount1.add(amount1Delta.mul(convertTo18Decimals(1000)).div(convertTo18Decimals(1001))).sub(3)
        )
      })
    })
  })
})
