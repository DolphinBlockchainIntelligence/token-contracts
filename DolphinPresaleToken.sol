pragma solidity ^0.4.13;
import "github.com/oraclize/ethereum-api/oraclizeAPI.sol";

contract CMCEthereumTicker is usingOraclize {
    
    uint centsPerETH;
    bool enabled;
    
    address parent;
    address manager;
    
    modifier onlyParentOrManager() { require(msg.sender == parent || msg.sender == manager); _; }
    
    event newOraclizeQuery(string description);
    event newPriceTicker(string price);
    
    
    function CMCEthereumTicker(address _manager) {
        oraclize_setProof(proofType_NONE);
        enabled = false;
        parent = msg.sender;
        manager = _manager;
    }
    
    function getCentsPerETH() constant returns(uint) {
        return centsPerETH;
    }
    
    function getEnabled() constant returns(bool) {
        return enabled;
    }
    
    function enable() 
        onlyParentOrManager
    {
        require(enabled == false);
        enabled = true;
        update_instant();
    }
    
    function disable() 
        onlyParentOrManager
    {
        require(enabled == true);
        enabled = false;
    }
    
    function __callback(bytes32 myid, string result) {
        if (msg.sender != oraclize_cbAddress()) revert();
        centsPerETH = parseInt(result, 2);
        newPriceTicker(result);
        if (enabled) {
           update(); 
        }
    }
    
    function update_instant() payable {
        if (oraclize.getPrice("URL") > this.balance) {
            newOraclizeQuery("Oraclize query was NOT sent, please add some ETH to cover for the query fee");
        } else {
            newOraclizeQuery("Oraclize query was sent, standing by for the answer..");
            oraclize_query("URL", "json(https://api.coinmarketcap.com/v1/ticker/ethereum/?convert=USD).0.price_usd");
        }
    }
    
    function update() payable {
        if (oraclize.getPrice("URL") > this.balance) {
            newOraclizeQuery("Oraclize query was NOT sent, please add some ETH to cover for the query fee");
        } else {
            newOraclizeQuery("Oraclize query was sent, standing by for the answer..");
            oraclize_query(60, "URL", "json(https://api.coinmarketcap.com/v1/ticker/ethereum/?convert=USD).0.price_usd");
        }
    }
    
    function payToManager(uint _amount) 
        onlyParentOrManager
    {
        if(!manager.send(_amount)) revert();
    }
    
    function () payable {}
    
}

contract PresaleToken {


    function PresaleToken(uint _limitUSD, uint _priceCents) {
        tokenManager = msg.sender;
        priceCents = _priceCents;
        ///maxSupply = 100 * _limitUSD/_priceCents * uint(10)**decimals;
        maxSupply = uint(10)**decimals * 100 * _limitUSD/_priceCents;
    }
    
    enum Phase {
        Created,
        Running,
        Finished,
        Finalized,
        Migrating,
        Migrated
    }
    
    // maximum token supply
    uint public maxSupply;
    // price of 1 token in USD cents
    uint public priceCents;
    // Ticker contract
    CMCEthereumTicker priceTicker;

    
    //Phase on contract creation
    Phase public currentPhase = Phase.Created;

    // amount of tokens already sold
    uint private supply = 0; 

    // Token manager has exclusive priveleges to call administrative
    // functions on this contract.
    address public tokenManager;
    // Migration manager has privileges to burn tokens during migration.
    address public migrationManager;
    
    // The last buyer is the buyer that purchased
    // tokens that add up to the maxSupply or more.
    // During the presale finalization they are refunded
    // the excess USD according to lastCentsPerETH.
    address lastBuyer;
    uint refundValue = 0;
    uint lastCentsPerETH = 0;
    
    //ERC 20 Containers
    mapping (address => uint256) private balance;
    mapping (address => mapping(address => uint256)) private allowed;
    
    //ERC 20 Additional info
    string public constant name = "Dolphin Presale Token";
    string public constant symbol = "DBIP";
    uint8 public constant decimals = 18;

    //External access modifiers
    modifier onlyTokenManager()     { require(msg.sender == tokenManager); _; }
    modifier onlyMigrationManager() { require(msg.sender == migrationManager); _; }
    //Presale phase modifiers
    modifier onlyWhileCreated() {assert(currentPhase == Phase.Created); _;}
    modifier onlyWhileRunning() {assert(currentPhase == Phase.Running); _;}
    modifier onlyWhileFinished() {assert(currentPhase == Phase.Finished); _;}
    modifier onlyWhileFinalized() {assert(currentPhase == Phase.Finalized); _;}
    modifier onlyBeforeMigration() {assert(currentPhase != Phase.Migrating && currentPhase != Phase.Migrated); _;}
    modifier onlyWhileMigrating() {assert(currentPhase == Phase.Migrating); _;}

    

    event LogBuy(address indexed owner, uint value, uint centsPerETH);
    event LogMigrate(address indexed owner, uint value);
    event LogPhaseSwitch(Phase newPhase);
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);


    
    function() payable {
        buyTokens(msg.sender);
    }
    

    ///ERC20 Interface functions
    
    function balanceOf(address _owner) constant returns (uint256 balanceOf) {
        return balance[_owner];
    }
    
    function totalSupply() constant returns (uint256 totalSupply) {
        return supply;
    }
    
    function allowance(address _owner, address _spender) constant returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }

    function transfer(address _to, uint256 _value) onlyBeforeMigration returns (bool success) 
    {
        if (balance[msg.sender] >= _value && _value > 0) {
            balance[msg.sender] -= _value;
            balance[_to] += _value;
            Transfer(msg.sender,_to,_value);
            return true;
        }
        return false;
    }
    
    function approve(address _spender, uint256 _value) onlyBeforeMigration returns (bool success) {
        if (balance[msg.sender] >= _value && _value > 0) {
            allowed[msg.sender][_spender] = _value;
            Approval(msg.sender,_spender,_value);
            return true;
        }
        return false;
    }
    
    
    function transferFrom(address _from, address _to, uint256 _value) onlyBeforeMigration returns (bool success) {
        
        if (allowed[_from][msg.sender] >= _value && balance[_from] >= _value && _value >= 0) 
        {
            allowed[_from][msg.sender] -= _value;
            balance[_from] -= _value;
            balance[_to] += _value;
            Transfer(_from,_to,_value);
            return true;
        }
        
        return false;
    }

    ///Presale-specific functions

    function buyTokens(address _buyer) payable
        onlyWhileRunning
    {
        require(msg.value != 0);
        require(priceTicker.getEnabled());
        require(priceTicker.getCentsPerETH() != 0);
        var centsPerETH = getCentsPerETH();
        var newTokens = msg.value * centsPerETH * uint(10)**decimals  / (priceCents  * (1 ether / 1 wei));
        assert(newTokens != 0);
        
        if (supply + newTokens > maxSupply) {
            var remainder = maxSupply - supply;
            balance[_buyer] += remainder;
            supply += remainder;
            lastBuyer = _buyer;
            refundValue = newTokens - remainder;
            LogBuy(_buyer, remainder, centsPerETH);
        }
        else {
            balance[_buyer] += newTokens;
            supply += newTokens;
            LogBuy(_buyer, newTokens, centsPerETH);
        }
        
        if (supply == maxSupply) {
            lastCentsPerETH = centsPerETH;
            currentPhase = Phase.Finished;
            LogPhaseSwitch(Phase.Finished);
        }
    }

    function migrateTokens(address _owner)
        onlyMigrationManager
        onlyWhileMigrating
    {
        assert(balance[_owner] != 0);
        var migratedValue = balance[_owner];
        supply -= migratedValue;
        balance[_owner] = 0;
        LogMigrate(_owner, migratedValue);

        if(supply == 0) {
            currentPhase = Phase.Migrated;
            LogPhaseSwitch(Phase.Migrated);
        }
    }

    function startPresale()
        onlyTokenManager
        onlyWhileCreated
    {
        assert(address(priceTicker) != 0x0);
        currentPhase = Phase.Running;
        LogPhaseSwitch(Phase.Running);
    }
    
    function finishPresale()
        onlyTokenManager
        onlyWhileRunning
    {
        lastCentsPerETH = priceTicker.getCentsPerETH();
        currentPhase = Phase.Finished;
        LogPhaseSwitch(Phase.Finished);
    }

    
    function finalizePresale()
        onlyTokenManager
        onlyWhileFinished
    {   
        if (refundValue != 0) {
            if(!lastBuyer.send((refundValue * priceCents * (1 ether / 1 wei)) / (lastCentsPerETH * uint(10)**decimals))) revert();
        }
        withdrawEther();
        currentPhase = Phase.Finalized;
        LogPhaseSwitch(Phase.Finalized);
    }

    function startMigration()
        onlyTokenManager
        onlyWhileFinalized
    {
        assert(migrationManager != 0x0);
        currentPhase = Phase.Migrating;
        LogPhaseSwitch(Phase.Migrating);
    }

    function withdrawEther() private
    {
        if(this.balance > 0) {
            if(!tokenManager.send(this.balance)) revert();
        }
    }

    function setMigrationManager(address _mgr)
        onlyTokenManager
        onlyWhileFinalized
    {
        migrationManager = _mgr;
    }
    
    function raiseCap(uint _newCap)
        onlyTokenManager
        onlyWhileFinalized
    {
        assert(_newCap > maxSupply);
        maxSupply = _newCap;
        currentPhase = Phase.Running;
        LogPhaseSwitch(Phase.Running);
    }
    
    function giveTokens(address _address, uint _value) 
        onlyTokenManager
        onlyBeforeMigration
        
    {
        balance[_address] += _value;
        supply += _value;
    }
    
    ///Ticker interaction functions
    
    function createTicker() 
        onlyTokenManager
    {
        priceTicker = new CMCEthereumTicker(tokenManager);
    }
    
    function attachTicker(address _tickerAddress)
        onlyTokenManager
    {
         priceTicker = CMCEthereumTicker(_tickerAddress);   
    }
    
    function enableTicker() 
        onlyTokenManager
    {
        priceTicker.enable();
    }
    
    function disableTicker() 
        onlyTokenManager
    {
        priceTicker.disable();
    }
    
    function sendToTicker() payable
        onlyTokenManager
    {
        assert(address(priceTicker) != 0x0);
        if(!address(priceTicker).send(msg.value)) revert();
    }
    
    function withdrawFromTicker(uint _amount) {
        assert(address(priceTicker) != 0x0);
        priceTicker.payToManager(_amount);
    }
    
    function tickerAddress() constant returns (address) {
        return address(priceTicker);
    }
    
    function getCentsPerETH() constant returns (uint) {
        return priceTicker.getCentsPerETH();
    }
    
}