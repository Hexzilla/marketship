var GameItem = artifacts.require("GameItem");
var Market = artifacts.require("Market");

module.exports = function (deployer) {
	deployer.then(function () {
		return deployer.deploy(GameItem).then(function (gameItem) {
            return deployer.deploy(Market, gameItem.address).then(async function (market) {
                return gameItem.addMinter(market.address)
            })
		})
	})
}