const Mercury = artifacts.require("Mercury");
const Market = artifacts.require("Market");
const Resolver = artifacts.require("Resolver");
const Rent = artifacts.require("Rent");

/*module.exports = function (deployer) {
	deployer.then(function () {
		return deployer.deploy(Mercury).then(function (mercury) {
            return deployer.deploy(Market, mercury.address).then(async function (market) {
                return mercury.addMinter(market.address)
            })
		})
	})
}*/

module.exports = async function (deployer) {
	console.log("deployer:", deployer)
	const mercury = await deployer.deploy(Mercury);
	const market = await deployer.deploy(Market, mercury.address);
	mercury.addMinter(market.address);
	//const resolver = await deployer.deploy(Resolver, deployer);
}
