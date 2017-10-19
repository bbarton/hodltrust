pragma solidity ^0.4.17;

/// @title HODL Trust (hodltrust.com)
/// @author Bevan Barton

/* An experimental decentralized trust with tokens and dividend program. */


/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a * b;
        assert(a == 0 || c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}


/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 */
 contract Ownable {
    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        if (newOwner != address(0))
            owner = newOwner;
    }
}


contract Token is Ownable {

    using SafeMath for uint256;

    string public name = "HODL Trust";
    string public symbol = "HODL";
    uint public decimals = 18;
    uint public totalSupply;

    mapping (address => uint256) balances;       // Each user's current HODL-coin balance.
    mapping (address => mapping (address => uint256)) allowed;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed ownerAddress, address indexed spenderAddress, uint256 value);
    event Mint(address indexed to, uint256 amount);
    event MineFinished();

    function balanceOf(address _owner) public view returns (uint256 balance) {
        return balances[_owner];
    }

    function transfer(address _to, uint256 _value) public returns (bool) { }

    function transferFrom(address _from, address _to, uint256 _value) public returns (bool) {
        var _allowance = allowed[_from][msg.sender];
        // Check is not needed because sub(_allowance, _value) will already throw if this condition is not met
        // require (_value <= _allowance);
        balances[_to] = balances[_to].add(_value);
        balances[_from] = balances[_from].sub(_value);
        allowed[_from][msg.sender] = _allowance.sub(_value);
        Transfer(_from, _to, _value);
        return true;
    }

    /**
    * @dev Aprove the passed address to spend the specified amount of tokens on behalf of msg.sender.
    * @param _spender The address which will spend the funds.
    * @param _value The amount of tokens to be spent.
    */
    function approve(address _spender, uint256 _value) public returns (bool) {
        // To change the approve amount you first have to reduce the addresses`
        //  allowance to zero by calling `approve(_spender, 0)` if it is not
        //  already 0 to mitigate the race condition described here:
        //  https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
        require((_value == 0) || (allowed[msg.sender][_spender] == 0));

        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
        return true;
    }

    /**
    * @dev Function to check the amount of tokens that an owner allowed to a spender.
    * @param _owner address The address which owns the funds.
    * @param _spender address The address which will spend the funds.
    * @return A uint256 specifing the amount of tokens still avaible for the spender.
    */
    function allowance(address _owner, address _spender) public view returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }

    /**
    * @dev Function to mint tokens
    * @param _to The address that will recieve the minted tokens.
    * @param _amount The amount of tokens to mint.
    * @return A boolean that indicates if the operation was successful.
    */
    function mint(address _to, uint256 _amount) internal returns (bool) {}

}

contract HodlTrust is Token {

    uint public totalSupply;        // Total amount of HODL-coins in circulation.
    uint public totalDividends;     // The cumulative amount of dividends (redistributed Trusts) issued.
    uint public secondsToClaim;     // How much time the investor has to claim their ETH after their Trust expires.
    bool public emergencyShutOff;   // If enabled, no new Trusts can be created and all Trusts are immediately retractable by their beneficiaries. Triggered by contract owner in case of unforeseen emergency.
    uint public lapsedAccountYears; // How many years it takes for an Account to lapse (at which point the public can reclaim its HODL-coin balance and dividendOwed, but not the Trusts they're entitled to).

    mapping (address => Account) public accounts;            // Store all accounts keyed by owner address.
    mapping (address => uint[]) public grantorTrustIDs;      // Maps Trust creator addresses to IDs of the Trusts they've created.
    mapping (address => uint[]) public beneficiaryTrustIDs;  // Maps Trust beneficiary addresses to IDs of the Trusts they're the beneficiaries of.
    Trust[] public trusts;             // The index is the ID of each Trust
    address[] public addressList;      // All addresses of Account-holders.

    // Accounts are created for all users (Trust creators, beneficiaries, receivers of HODL).
    struct Account {
        address addr;           // The beneficiary of the account (but not necessarily of a Trust).
        uint lastTotalDividends;// Stores the value of totalDividends the last time updateOwedFor() was called (when their HODL-coin balance changed). Used to calculate how much they can withdraw at any time.
        uint dividendOwed;      // Dividends they are currently owed (in ethereum). Set by calling updateOwedFor(). They can then cashOut() this amount.
        uint publicClaimed;     // For lapsed accounts. Stores the date this account's dividendOwed and HODL balance were redistributed to the community.
        uint lastAction;        // The date of the last action performed by this account. Used to determine if an Account has lapsed (and can be publicly redistributed).
    }

    struct Trust {
        address beneficiary;      // Addresses of the beneficiary.
        uint amount;              // Amount of ETH being HODLed.
        uint releaseDate;         // The ETH amount can be released to the beneficiary after this block.
        uint publicReleaseDate;   // The ETH amount can be released to the public after this block.
        bool claimed;             // Has the beneficiary claimed this Trust?
        bool publicClaimed;       // Has the community claimed this Trust?
    }

    event TrustAdded(address creatorAddress, uint amount, uint releaseDate, uint publicReleaseDate, uint trustId);
    event RedistributeUnclaimed(address caller, uint amountRedistributed);
    event RedistributeLapsedAccount(address accountAddr, uint reclaimedEthdividendOwed);

    function HodlTrust() {
        owner = msg.sender;
        secondsToClaim = 200; //31540000; // Investors have 1 year from the releaseDate to claim their Trust. After that, it can be redistributed to token holders.
        lapsedAccountYears = 5; // If an account is inactive for this many years, its dividendOwed and HODL-coin balance can be redistributed.
    }

    /// @notice Store ether for `_durationMonths` months. Only `_beneficiary` can retract.
    /// Specify whether you'd like to receive HODL coins and impose a 1-year withdrawal period (`_dividendProgram`).
    /// @param _beneficiary The address of the beneficiary of this trust.
    /// @param _durationMonths The contract will hold the ether for this number of months. The beneficiary can withdraw after this period.
    /// @param _dividendProgram Pass true to receive HODL coins, which also limits the time for the beneficiary to withdraw to one year.
    /// Passing false gives a one-hundred year withdrawal period.
    function addTrust(address _beneficiary, uint _durationMonths, bool _dividendProgram) public payable returns (uint) {
        uint amount = msg.value;
        require(amount > 0);
        require(!emergencyShutOff);

        uint durationSeconds = _durationMonths;// TODO: _durationMonths * 30 * 24 * 60 * 60;

        // Trust dates must be at least 1 year from now, and max 10 years from now.
        uint minTime = 60; //31540000;  // 1 year in seconds.
        uint maxTime = 600; // 10 min //315400000; // 10 years

        require(durationSeconds > minTime);
        require(durationSeconds < maxTime);

        uint releaseDate = block.timestamp + durationSeconds; // Ether can be claimed by beneficiary after this date. 
        uint pubReleaseDate; // When the Trust lapses (when the Trust's ether can be redistributed to the public)

        // If the grantor has elected to receive HODL coins (and given up the long claim period),
        // give the beneficiary a one-year period in which to claim their Trust.  
        if (_dividendProgram)
            pubReleaseDate = releaseDate + secondsToClaim;
        else
            pubReleaseDate = releaseDate + (31540000 * 100);   // If they opt out of receiving coins, give the beneficiary 100 years to cash out.

        // Create the Trust record.
        uint id = trusts.length++;
        trusts[id] = Trust({
            beneficiary: _beneficiary, 
            amount: amount, 
            releaseDate: releaseDate, 
            publicReleaseDate: pubReleaseDate, 
            claimed: false, 
            publicClaimed: false});

        // Store a reference to this Trust in the creator's array of Trust IDs.
        uint gtLength = grantorTrustIDs[_beneficiary].length++;
        grantorTrustIDs[msg.sender][gtLength] = id;
        // Store a reference to this Trust in the beneficiary's array of Trust IDs.
        uint btLength = beneficiaryTrustIDs[_beneficiary].length++;
        beneficiaryTrustIDs[msg.sender][btLength] = id;
        // Create Account for the message sender and beneficiary if they don't already exist.
        createAccount(msg.sender);
        createAccount(_beneficiary);
        // Credit the Trust creator one HODL token for every ethereum-year they've committed to (trust 2 ethereum for 1.5 years = 3.0 HODL tokens)
        // "mintEthYears" also updates their dividendOwed, since they may have unclaimed dividends.
        if (_dividendProgram)
            mintEthYears(msg.sender, amount, durationSeconds); // This sets account.lastAction
        TrustAdded(msg.sender, amount, releaseDate, pubReleaseDate, id);
    }

    /// @dev Create an account. This is now called upon receiving a transfer.
    /// @param _addr The address of the account holder.
    function createAccount(address _addr) public {
        if (accounts[_addr].addr == 0x0) {
            accounts[_addr] = Account({
                addr: _addr, 
                lastTotalDividends: totalDividends, 
                dividendOwed: 0, 
                publicClaimed: 0, 
                lastAction: block.timestamp});
            uint l = addressList.length++;
            addressList[l] = _addr;  // Add the address to an array for ease of querying (with getAddressList(id)).
        }
    }

    /// @dev Mints HODL coins for a Trust creator as a function of the ether amount and trust duration.
    /// @param _to Trust creator / recipient of HODL coins.
    /// @param _weiAmount Amount of ether deposited.
    /// @param _durationSeconds The hodl period of the trust.
    function mintEthYears(address _to, uint256 _weiAmount, uint256 _durationSeconds) internal {
        // Before minting, lock in the dividend amount owed to the recipient with their current balance.
        updateOwedFor(_to);
        // Mint one token for every ether-year the user has committed to.
        uint oneYear = 31540000;  // 1 year in seconds.
        uint hodlTokensToAward = _weiAmount.mul(_durationSeconds).div(oneYear);
        totalSupply = totalSupply.add(hodlTokensToAward);
        balances[_to] = balances[_to].add(hodlTokensToAward);
        setLastAction(_to);
        Mint(_to, hodlTokensToAward);
    }

    /// @dev Update the amount of dividends owed to `_acct`.
    /// This function asks: have new dividends been issued since we last ran this function?
    /// If so, credit this account its share of the uncredited dividends.
    function updateOwedFor(address _acct) public {
        Account storage acct = accounts[_acct];
        // If the current amount of dividends available is greater than what we last recorded
        // in acct.lastTotalDividends, then credit this user their share of the difference.
        if (totalDividends > acct.lastTotalDividends) {
            // Increment dividendOwed by the user's share of the unclaimed dividends.
            acct.dividendOwed = acct.dividendOwed.add(totalDividends.sub(acct.lastTotalDividends).mul(balances[acct.addr]).div(totalSupply));
            // Set lastTotalDividends, so that we don't credit this user again until another dividend is issued.
            acct.lastTotalDividends = totalDividends;
        }
    }

    /// @notice Retract ether from a Trust you're entitled to.
    /// @param _trustID Trust ID
    function claim(uint _trustID) public {
        require(canClaim(_trustID));
        Trust storage trust = trusts[_trustID];
        trust.claimed = true;
        trust.beneficiary.transfer(trust.amount);
        setLastAction(trust.beneficiary);
    }

    /// @dev Check if the caller can claim Trust `_trustID`.
    /// @param _trustID Trust ID.
    /// @return Whether the trust can be claimed.
    function canClaim(uint _trustID) public view returns (bool) {
        Trust storage trust = trusts[_trustID];
        if ((msg.sender == trust.beneficiary) &&
            (trust.claimed == false) &&
            (trust.publicClaimed == false) &&
            ((block.timestamp > trust.releaseDate) || emergencyShutOff)) { // Must be ready to be claimed, or emergencyShutOff must be activated. 
            return true;
        } else {
            return false;
        }
    }

    /// @dev When can the beneficiary claim this Trust? (seconds from now)
    /// @param _trustID Trust ID
    /// @return Number of seconds in the future.
    function canClaimIn(uint _trustID) public view returns (uint) {
        Trust storage trust = trusts[_trustID];
        if ((block.timestamp > trust.releaseDate) || emergencyShutOff)
            return 0;
        else
            return trust.releaseDate.sub(block.timestamp);
    }

    /// @notice Redistributes the Trust to HODL coin-bearers (Trust #`_trustID`).
    /// @dev Adds the ether amount to the totalDividends counter, which HODL-token holders can claim from.
    function redistributeUnclaimed(uint _trustID) public {
        Trust storage h = trusts[_trustID];
        require(!h.claimed);
        require(!h.publicClaimed);
        require(msg.sender != h.beneficiary); // Prevent the beneficiary from accidentally redistributing their Trust.
        require(block.timestamp > h.publicReleaseDate);   // emergencyShutOff does not affect when the public can claim this Trust.

        h.publicClaimed = true;
        totalDividends += h.amount; // Add the amount of the Trust to the totalDividends counter.
        setLastAction(msg.sender);
        RedistributeUnclaimed(msg.sender, h.amount);
    }

    /// @dev Check when a Trust is eligible for public redistribution (seconds from now).
    /// @param trustID Trust ID
    /// @return Seconds until this trust can be claimed.
    function canRedistributeUnclaimedIn(uint trustID) public view returns (uint) {
        Trust storage trust = trusts[trustID];
        if (block.timestamp > trust.publicReleaseDate)
            return 0;
        else
            return trust.publicReleaseDate.sub(block.timestamp);
    }

    /// @notice Redistribute a lapsed account's dividendsOwed.
    /// @dev A lapsed account is one that hasn't been active in 5 years
    /// (i.e. hasn't created a Trust, claimed a Trust or account, or sent or received a transfer).
    /// Does not redistribute HODL coins or impact the ability of the lapsed account to claim its Trusts.
    function redistributeLapsedAccount(address _accountAddr) public {
        Account storage a = accounts[_accountAddr];
        require(canRedistributeLapsedAccount(_accountAddr));
        /* Transfer the account's dividendOwed to the public totalDividends account. */
        uint reclaimedEthDividendOwed = a.dividendOwed;
        if (reclaimedEthDividendOwed > 0) {
            totalDividends = totalDividends.add(reclaimedEthDividendOwed);
            a.dividendOwed = 0;
        }
        a.publicClaimed = block.timestamp;  // Record the date this account was publicly claimed.
        setLastAction(msg.sender);
        RedistributeLapsedAccount(_accountAddr, reclaimedEthDividendOwed);
    }

    /// @dev Whether an account has lapsed and its dividendOwed can be redistributed.
    /// @param _accountAddr Account address.
    /// @return Whether an account has lapsed and its dividendOwed can be redistributed.
    function canRedistributeLapsedAccount(address _accountAddr) public view returns (bool) {
        Account storage a = accounts[_accountAddr];
        bool isLapsed = (block.timestamp > (a.lastAction + (lapsedAccountYears * 31540000)));
        bool hasdividendOwed = a.dividendOwed > 0;
        if (isLapsed && hasdividendOwed)
            return true;
        else
            return false;
    }

    /// @dev Set an Account's lastAction (to prevent it from lapsing).
    /// Anyone can call this; but it is called automatically on the caller of most persistent functions.
    function setLastAction(address _accountAddr) public {
        Account storage a = accounts[_accountAddr];
        a.lastAction = block.timestamp;
    }

    /// @notice Cash out dividends owed to your account.
    /// First: ensure your dividendsOwed is current by sending or receiving HODL coins, or calling updateOwedFor(yourAddress).
    /// To claim a Trust that you are the beneficiary of, use claim(trustID) instead.
    function cashOut() public {
        Account storage acct = accounts[msg.sender];
        uint amtOwed = acct.dividendOwed;
        acct.dividendOwed = 0;
        msg.sender.transfer(amtOwed);
    }

    /// @dev Transfer HODL coins.
    /// Before the transfer, updates dividendOwed for sender and receiver.
    /// Sets lastAction for both parties.
    /// @return Transaction status.
    function transfer(address _to, uint256 _value) public returns (bool) {
        if (msg.data.length < (2 * 32) + 4)
            revert();
        // Create an Account for the recipient so they can claim dividends with their HODL-coin balance.
        if (accounts[_to].addr == 0x0)
            createAccount(_to);
        // Before transferring tokens, update the award amount owed to the sender and receiver.
        updateOwedFor(msg.sender);
        updateOwedFor(_to);
        // Perform the transfer.
        balances[msg.sender] = balances[msg.sender].sub(_value);
        balances[_to] = balances[_to].add(_value);
        setLastAction(msg.sender);
        setLastAction(_to);
        Transfer(msg.sender, _to, _value);
        return true;
    }

    /// @dev The owner can disable this contract, thereby preventing new Trusts from being created
    /// and letting the beneficiaries cash out their Trusts immediately.
    /// It does not affect when Trusts can be redistributed.
    /// It does not prevent tokens from being transferred.
    function shutOff() public onlyOwner { emergencyShutOff = true; }

    /* Accessor functions for front-end: */

    /// @dev Return information from an Account struct.
    /// @param _address Account address.
    /// @return All Account struct fields.
    function getAccount(address _address) public view returns (address addr, uint lastTotalDividends, uint dividendOwed, uint publicClaimed, 
        uint lastAction) {
        Account storage a = accounts[_address];
        addr = a.addr;
        lastTotalDividends = a.lastTotalDividends;
        dividendOwed = a.dividendOwed;
        publicClaimed = a.publicClaimed;
        lastAction = a.lastAction;
    }

    /// @dev Return information from a Trust struct.
    /// @param _trustID Trust ID.
    /// @return All Trust struct fields.
    function getTrust(uint _trustID) public view returns (address beneficiary, uint amount, uint releaseDate, uint publicReleaseDate, bool claimed, bool publicClaimed) {
        Trust storage t = trusts[_trustID];
        beneficiary = t.beneficiary;
        amount = t.amount;
        releaseDate = t.releaseDate;
        publicReleaseDate = t.publicReleaseDate;
        claimed = t.claimed;
        publicClaimed = t.publicClaimed;
    }

    /// @dev Get the IDs of Trusts that have been created by `_grantorAddress`.
    /// @param _grantorAddress Grantor's address.
    /// @return IDs of this grantor's trusts.
    function getGrantorTrusts(address _grantorAddress) public view returns (uint[]) {
        return grantorTrustIDs[_grantorAddress];
    }

    /// @dev Get the IDs of Trusts whose beneficiary is `_beneficiaryAddress`.
    /// @param _beneficiaryAddress Beneficiary's address.
    /// @return IDs of this beneficiary's trusts.
    function getBeneficiaryTrusts(address _beneficiaryAddress) public view returns (uint[]) {
        return beneficiaryTrustIDs[_beneficiaryAddress];
    }

    /* Convenience functions: */

    /// @dev Get number of Trusts.
    /// @return Number of trusts.
    function getNumberOfTrusts() public view returns (uint) {
        return trusts.length;
    }

    /// @dev Get list of addresses that have Accounts.
    /// @return List of addresses.
    function getAddressList() public view returns (address[]) {
        return addressList;
    }

    /// @dev Get contract balance.
    /// @return Contract balance.
    function getBalance() public view returns (uint) {
        return this.balance;
    }

    /// @dev Get timestamp.
    /// @return Timestamp.
    function timestamp() public view returns (uint) {
        return block.timestamp;
    }
}
