import { IUniswapV3Factory } from './../../typechain/IUniswapV3Factory'
import { Fixture } from 'ethereum-waffle'
import { ethers, upgrades } from 'hardhat'
import { constants, Wallet } from 'ethers'
import { UniswapV3FactoryAddress } from './address'
import { MockERC20, MockYANG, CHIVaultDeployer, CHIManager, MockRouter } from '../../typechain'
import parseWhiteListMap from './parse-whitelist-map'

interface IUniswapV3FactoryFixture {
  uniswapV3Factory: IUniswapV3Factory
}

async function uniswapVfactoryFixture(): Promise<IUniswapV3FactoryFixture> {
  const uniswapV3Factory = (await ethers.getContractAt(
    'IUniswapV3Factory',
    UniswapV3FactoryAddress
  )) as IUniswapV3Factory
  return { uniswapV3Factory }
}

interface TokensFixture {
  token0: MockERC20
  token1: MockERC20
  token2: MockERC20
}

async function tokensFixture(): Promise<TokensFixture> {
  const tokenFactory = await ethers.getContractFactory('MockERC20')
  const tokens = (await Promise.all([
    tokenFactory.deploy(constants.MaxUint256.div(2)),
    tokenFactory.deploy(constants.MaxUint256.div(2)),
    tokenFactory.deploy(constants.MaxUint256.div(2)),
  ])) as [MockERC20, MockERC20, MockERC20]

  const [token0, token1, token2] = tokens.sort((tokenA, tokenB) =>
    tokenA.address.toLowerCase() < tokenB.address.toLowerCase() ? -1 : 1
  )

  return { token0, token1, token2 }
}

interface YangFixture {
  yang: MockYANG
}

async function yangFixture(): Promise<YangFixture> {
  const MockYANGFactory = await ethers.getContractFactory('MockYANG')
  const yang = (await MockYANGFactory.deploy()) as MockYANG
  return { yang }
}

interface chiVaultDeployerFixture {
  chiVaultDeployer: CHIVaultDeployer
}

async function chiVaultDeployerFixture(): Promise<chiVaultDeployerFixture> {
  const chiVaultDeployerFactory = await ethers.getContractFactory('CHIVaultDeployer')
  const chiVaultDeployer = (await chiVaultDeployerFactory.deploy()) as CHIVaultDeployer
  return { chiVaultDeployer }
}

interface ChiManagerFixture {
  chi: CHIManager
}

async function chiManagerFixture(
  yangAddress: string,
  vaultDeployerAddress: string,
  wallets: Wallet[]
): Promise<ChiManagerFixture> {
  const info = parseWhiteListMap([wallets[0].address])
  const chiManagerFactory = await ethers.getContractFactory('CHIManager')
  const chi = (await upgrades.deployProxy(
      chiManagerFactory,
      [1, UniswapV3FactoryAddress, yangAddress, vaultDeployerAddress, info.merkleRoot, 70000]
  )) as CHIManager
  return { chi }
}

interface RouterFixture {
  router: MockRouter
}

async function routerFixture(): Promise<RouterFixture> {
  const routerFactory = await ethers.getContractFactory('MockRouter')
  const router = (await routerFactory.deploy()) as MockRouter
  return { router }
}

type AllFixture = IUniswapV3FactoryFixture &
  TokensFixture &
  YangFixture &
  chiVaultDeployerFixture &
  ChiManagerFixture &
  RouterFixture

export const allFixture: Fixture<AllFixture> = async function (wallet: Wallet[]) {
  const { uniswapV3Factory } = await uniswapVfactoryFixture()
  const { token0, token1, token2 } = await tokensFixture()
  const { yang } = await yangFixture()
  const { chiVaultDeployer } = await chiVaultDeployerFixture()
  const { chi } = await chiManagerFixture(yang.address, chiVaultDeployer.address, wallet)
  const { router } = await routerFixture()

  await chiVaultDeployer.setCHIManager(chi.address)
  await yang.setCHIManager(chi.address)

  return {
    uniswapV3Factory,
    token0,
    token1,
    token2,
    yang,
    chiVaultDeployer,
    chi,
    router,
  }
}
