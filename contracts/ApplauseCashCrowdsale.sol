pragma solidity ^0.4.18;


import "./Ownable.sol";
import "./SafeMath.sol";
import "./ApplauseCashToken.sol";
import "./RefundVault.sol";

/**
 * @title Crowdsale
 * @dev Modified contract for managing a token crowdsale.
 * ApplauseCashCrowdsale have pre-sale and main sale periods,
 * where investors can make token purchases and the crowdsale will assign
 * them tokens based on a token per ETH rate and the system of bonuses.
 * Funds collected are forwarded to a wallet as they arrive.
 * pre-sale and main sale periods both have caps defined in tokens.
 */

contract ApplauseCashCrowdsale is Ownable {

    using SafeMath for uint256;

    struct Bonus {
        uint duration;
        uint percent;
    }

    // minimum amount of funds to be raised in tokens
    uint256 public softcap;

    // refund vault used to hold funds while crowdsale is running
    RefundVault public vault;

    // true for finalised crowdsale
    bool public isFinalized;

    // The token being sold
    ApplauseCashToken public token = new ApplauseCashToken();

    // start and end timestamps where pre-investments are allowed (both inclusive)
    uint256 public preIcoStartTime;
    uint256 public preIcoEndTime;

    // start and end timestamps where main-investments are allowed (both inclusive)
    uint256 public icoStartTime;
    uint256 public icoEndTime;

    // maximum amout of tokens for pre-sale and main sale
    uint256 public preIcoHardcap;
    uint256 public icoHardcap;

    // address where funds are collected
    address public wallet;

    // how many token units a buyer gets per ETH
    uint256 public rate;

    // amount of raised tokens
    uint256 public tokensInvested;

    Bonus[] public preIcoBonuses;
    Bonus[] public icoBonuses;

    // Invstors can't invest less then specified numbers in wei
    uint256 public preIcoMinimumWei;
    uint256 public icoMinimumWei;

    // Default bonus %
    uint256 public defaultPercent;

    /**
     * event for token purchase logging
     * @param purchaser who paid for the tokens
     * @param beneficiary who got the tokens
     * @param value weis paid for purchase
     * @param amount amount of tokens purchased
     */
    event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);

    function ApplauseCashCrowdsale(
        uint256 _preIcoStartTime,
        uint256 _preIcoEndTime,
        uint256 _preIcoHardcap,
        uint256 _icoStartTime,
        uint256 _icoEndTime,
        uint256 _icoHardcap,
        uint256 _softcap,
        uint256 _rate,
        address _wallet
    ) public {

        //require(_softcap > 0);

        // can't start pre-sale in the past
        require(_preIcoStartTime >= now);

        // can't start main sale in the past
        require(_icoStartTime >= now);

        // can't start main sale before the end of pre-sale
        require(_preIcoEndTime < _icoStartTime);

        // the end of pre-sale can't happen before it's start
        require(_preIcoStartTime < _preIcoEndTime);

        // the end of main sale can't happen before it's start
        require(_icoStartTime < _icoEndTime);

        require(_rate > 0);
        require(_preIcoHardcap > 0);
        require(_icoHardcap > 0);
        require(_wallet != 0x0);

        preIcoMinimumWei = 20000000000000000;  // 0.02 Ether default minimum
        icoMinimumWei = 20000000000000000; // 0.02 Ether default minimum
        defaultPercent = 0;

        preIcoBonuses.push(Bonus({duration: 1 hours, percent: 90}));
        preIcoBonuses.push(Bonus({duration: 6 days + 5 hours, percent: 50}));

        icoBonuses.push(Bonus({duration: 1 hours, percent: 45}));
        icoBonuses.push(Bonus({duration: 7 days + 15 hours, percent: 40}));
        icoBonuses.push(Bonus({duration: 6 days, percent: 30}));
        icoBonuses.push(Bonus({duration: 6 days, percent: 20}));
        icoBonuses.push(Bonus({duration: 7 days, percent: 10}));

        preIcoStartTime = _preIcoStartTime;
        preIcoEndTime = _preIcoEndTime;
        preIcoHardcap = _preIcoHardcap;
        icoStartTime = _icoStartTime;
        icoEndTime = _icoEndTime;
        icoHardcap = _icoHardcap;
        softcap = _softcap;
        rate = _rate;
        wallet = _wallet;

        isFinalized = false;

        vault = new RefundVault(wallet);
    }

    // fallback function can be used to buy tokens
    function () public payable {
        buyTokens(msg.sender);
    }

    // low level token purchase function
    function buyTokens(address beneficiary) public payable {

        require(beneficiary != 0x0);
        require(msg.value != 0);
        require(!isFinalized);

        uint256 weiAmount = msg.value;

        validateWithinPeriods();

        // calculate token amount to be created.
        // ETH and our tokens have different numbers of decimals after comma
        // ETH - 18 decimals, our tokes - 4. so we need to divide our value
        // by 1e14 (18 - 4 == 14).
        uint256 tokens = weiAmount.mul(rate).div(100000000000000);

        uint256 percent = getBonusPercent(now);

        // add bonus to tokens depends on the period
        uint256 bonusedTokens = applyBonus(tokens, percent);

        validateWithinCaps(bonusedTokens, weiAmount);

        // update state
        tokensInvested = tokensInvested.add(bonusedTokens);
        token.transfer(beneficiary, bonusedTokens);
        TokenPurchase(msg.sender, beneficiary, weiAmount, bonusedTokens);

        forwardFunds();
    }

    // set new dates for pre-salev (emergency case)
    function setPreIcoParameters(
        uint256 _preIcoStartTime,
        uint256 _preIcoEndTime,
        uint256 _preIcoHardcap,
        uint256 _preIcoMinimumWei
    ) public onlyOwner {
        require(!isFinalized);
        require(_preIcoStartTime < _preIcoEndTime);
        require(_preIcoHardcap > 0);
        preIcoStartTime = _preIcoStartTime;
        preIcoEndTime = _preIcoEndTime;
        preIcoHardcap = _preIcoHardcap;
        preIcoMinimumWei = _preIcoMinimumWei;
    }

    // set new dates for main-sale (emergency case)
    function setIcoParameters(
        uint256 _icoStartTime,
        uint256 _icoEndTime,
        uint256 _icoHardcap,
        uint256 _icoMinimumWei
    ) public onlyOwner {

        require(!isFinalized);
        require(_icoStartTime < _icoEndTime);
        require(_icoHardcap > 0);
        icoStartTime = _icoStartTime;
        icoEndTime = _icoEndTime;
        icoHardcap = _icoHardcap;
        icoMinimumWei = _icoMinimumWei;
    }

    // set new wallets (emergency case)
    function setWallet(address _wallet) public onlyOwner {
        require(!isFinalized);
        require(_wallet != 0x0);
        wallet = _wallet;
    }

      // set new rate (emergency case)
    function setRate(uint256 _rate) public onlyOwner {
        require(!isFinalized);
        require(_rate > 0);
        rate = _rate;
    }

        // set new softcap (emergency case)
    function setSoftcap(uint256 _softcap) public onlyOwner {
        require(!isFinalized);
        require(_softcap > 0);
        softcap = _softcap;
    }


    // set token on pause
    function pauseToken() external onlyOwner {
        require(!isFinalized);
        token.pause();
    }

    // unset token's pause
    function unpauseToken() external onlyOwner {
        token.unpause();
    }

    // set token Ownership
    function transferTokenOwnership(address newOwner) external onlyOwner {
        token.transferOwnership(newOwner);
    }

    // @return true if main sale event has ended
    function icoHasEnded() external constant returns (bool) {
        return now > icoEndTime;
    }

    // @return true if pre sale event has ended
    function preIcoHasEnded() external constant returns (bool) {
        return now > preIcoEndTime;
    }

    // send ether to the fund collection wallet
    function forwardFunds() internal {
        //wallet.transfer(msg.value);
        vault.deposit.value(msg.value)(msg.sender);
    }

    // we want to be able to check all bonuses in already deployed contract
    // that's why we pass currentTime as a parameter instead of using "now"
    function getBonusPercent(uint256 currentTime) public constant returns (uint256 percent) {
      //require(currentTime >= preIcoStartTime);
        uint i = 0;
        bool isPreIco = currentTime >= preIcoStartTime && currentTime <= preIcoEndTime;
        uint256 offset = 0;
        if (isPreIco) {
            uint256 preIcoDiffInSeconds = currentTime.sub(preIcoStartTime);
            for (i = 0; i < preIcoBonuses.length; i++) {
                if (preIcoDiffInSeconds <= preIcoBonuses[i].duration + offset) {
                    return preIcoBonuses[i].percent;
                }
                offset = offset.add(preIcoBonuses[i].duration);
            }
        } else {
            uint256 icoDiffInSeconds = currentTime.sub(icoStartTime);
            for (i = 0; i < icoBonuses.length; i++) {
                if (icoDiffInSeconds <= icoBonuses[i].duration + offset) {
                    return icoBonuses[i].percent;
                }
                offset = offset.add(icoBonuses[i].duration);
            }
        }
        return defaultPercent;
    }

    function applyBonus(uint256 tokens, uint256 percent) internal returns  (uint256 bonusedTokens) {
        uint256 tokensToAdd = tokens.mul(percent).div(100);
        return tokens.add(tokensToAdd);
    }

    function validateWithinPeriods() internal constant {
        // within pre-sale or main sale
        require((now >= preIcoStartTime && now <= preIcoEndTime) || (now >= icoStartTime && now <= icoEndTime));
    }

    function validateWithinCaps(uint256 tokensAmount, uint256 weiAmount) internal constant {
        uint256 expectedTokensInvested = tokensInvested.add(tokensAmount);

        // within pre-sale
        if (now >= preIcoStartTime && now <= preIcoEndTime) {
            require(weiAmount >= preIcoMinimumWei);
            require(expectedTokensInvested <= preIcoHardcap);
        }

        // within main sale
        if (now >= icoStartTime && now <= icoEndTime) {
            require(expectedTokensInvested <= icoHardcap);
        }
    }

    // if crowdsale is unsuccessful, investors can claim refunds here
    function claimRefund() public {
        require(isFinalized);
        require(!softcapReached());
        vault.refund(msg.sender);
    }

    function softcapReached() public constant returns (bool) {
        return tokensInvested >= softcap;
    }

    // finish crowdsale
    function finaliseCrowdsale() external onlyOwner returns (bool) {
        require(!isFinalized);
        if (softcapReached()) {
            vault.close();
        } else {
            vault.enableRefunds();
        }

        isFinalized = true;
        return true;
    }

}
