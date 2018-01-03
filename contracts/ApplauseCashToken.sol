pragma solidity ^0.4.18;

import "./StandardToken.sol";
import "./PausableToken.sol";


contract ApplauseCashToken is StandardToken, PausableToken {
    string public constant name = "ApplauseCash";
    string public constant symbol = "APLC";
    uint8 public constant decimals = 4;
    uint256 public INITIAL_SUPPLY = 300000000 * 10000;

    function ApplauseCashToken() public {
        totalSupply = INITIAL_SUPPLY;
        balances[msg.sender] = INITIAL_SUPPLY;
    }
}
