pragma solidity ^0.4.18;


import "./ApplouseCashCrowdsale.sol";
import "./Ownable.sol";


contract Deployer is Ownable {

    ApplouseCashCrowdsale public applouseCashCrowdsale;
    uint256 public constant TOKEN_DECIMALS_MULTIPLIER = 10000;
    address public multisig = 0xC767ABbA4c99F1a8F0Af726156f6c4E82745E32E;

    function deploy() public onlyOwner {
        applouseCashCrowdsale = new ApplouseCashCrowdsale(
            1516280400, //Pre ICO Start: 18 Jan 2018 at 8:00 am EST
            1516856400, //Pre ICO End: 24 Jan 2018 at 11:59 pm EST
            3000000 * TOKEN_DECIMALS_MULTIPLIER, //Pre ICO hardcap
            1517490000,  // ICO Start: 1 Feb 2018 at 8 am EST
            1519880400, // ICO End: 28 Feb 2018 at 11.59 pm EST
            144000000 * TOKEN_DECIMALS_MULTIPLIER,  // ICO hardcap
            50000 * TOKEN_DECIMALS_MULTIPLIER, // Overal crowdsale softcap
            500, // 1 ETH = 500 APLC
            multisig // Multisignature wallet (controlled by multiple accounts)
        );
    }

    function setOwner() public onlyOwner {
        applouseCashCrowdsale.transferOwnership(owner);
    }


}
