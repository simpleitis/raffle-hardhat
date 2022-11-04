const { network, ethers } = require("hardhat")
const { developmentChains } = require("../helper-hardhat-config")

// 'BASE_FEE' is the minimum oracle gas we need to spend when generating a random number, so when running the mock contract locally, out oracle gas would be ETH itself but in real world application which use mainnet, it would be LINK
const BASE_FEE = ethers.utils.parseEther("0.25")
// It is gas price per link. When we are using functions link 'checkUpKeep' and 'performUpKeep' the oracle pays the gas to get a random value and we then pay the oracle in terms of LINK
const GAS_PRICE_LINK = 1e9

// we are getting 'getNamedAccounts' and 'deployments' from 'hre'
module.exports = async function ({ getNamedAccounts, deployments }) {
    const { deploy, log } = deployments
    const { deployer } = await getNamedAccounts()
    const args = [BASE_FEE, GAS_PRICE_LINK]

    if (developmentChains.includes(network.name)) {
        log("Local network detected! Deploying mocks...")

        await deploy("VRFCoordinatorV2Mock", {
            from: deployer,
            log: true,
            args: args,
        })
        log("Mocks deployed!")
        log("---------------------------------------------")
    }
}

// tags can be used to specifically deploy scripts using 'yarn deploy --tags "mocks"'
module.exports.tags = ["all", "mocks"]
