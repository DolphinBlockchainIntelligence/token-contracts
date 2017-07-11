pragma solidity ^0.4.10;
import "github.com/oraclize/ethereum-api/oraclizeAPI.sol";

contract CMCEthereumTicker is usingOraclize {
    
    address parent;
    
    uint centsPerETH;
    bool cleanUpOn = false;
    
    event newOraclizeQuery(string description);
    event newPriceTicker(string price);
    
    
    function CMCEthereumTicker() {
        parent = msg.sender;
        update();
    }
    
    function getCentsPerETH() constant returns(uint centsPerETH) {
        return centsPerETH;
    }
    
    function __callback(bytes32 myid, string result, bytes proof) {
        if (msg.sender != oraclize_cbAddress()) throw;
        if (cleanUpOn) {
            selfdestruct(parent);
        }
        centsPerETH = parseInt(result, 2);
        newPriceTicker(result);
        update();
    }
    
    function update() payable {
        if (oraclize.getPrice("URL") > this.balance) {
            newOraclizeQuery("Oraclize query was NOT sent, please add some ETH to cover for the query fee");
        } else {
            newOraclizeQuery("Oraclize query was sent, standing by for the answer..");
            oraclize_query(60, "URL", "json(https://api.coinmarketcap.com/v1/ticker/ethereum/?convert=USD).0.price_usd");
        }
    }
    
    function initiateCleanUp() {
        assert(msg.sender == parent);
        cleanUpOn = true;
    }
}

contract PresaleToken {


    function PresaleToken(address _tokenManager, uint _limitUSD, uint _priceUSD) {
        tokenManager = _tokenManager;
        priceTicker = new CMCEthereumTicker();
        if(!priceTicker.send(this.balance)) throw;
        priceUSD = _priceUSD;
        maxSupply = _limitUSD/_priceUSD * 10**decimals;
    }
    
    enum Phase {
        Created,
        Running,
        Finished,
        Finalized,
        Migrating,
        Migrated
    }
    
    uint public maxSupply;
    uint public priceUSD;
    CMCEthereumTicker priceTicker;
    uint lastCentsPerETH = 0;
    
    string public constant name = "Dolphin BI Presale Token";
    string public constant symbol = "DBIP";
    uint8 public constant decimals = 8;
    
    Phase public currentPhase = Phase.Created;

    // amount of tokens already sold
    uint private supply = 0; 

    // Token manager has exclusive priveleges to call administrative
    // functions on this contract.
    address public tokenManager;
    // Crowdsale manager has exclusive priveleges to burn presale tokens.
    address public crowdsaleManager;
    
    // The last buyer is the buyer that purchased
    // tokens that add up to the maxSupply or more.
    // During the presale finalization they are refunded
    // the excess ether.
    address private lastBuyer;
    uint256 private refundValue;
    
    mapping (address => uint256) private balance;
    mapping (address => mapping(address => uint256)) private allowed;

    //external access modifiers
    modifier onlyTokenManager()     { if(msg.sender != tokenManager) throw; _; }
    modifier onlyCrowdsaleManager() { if(msg.sender != crowdsaleManager) throw; _; }
    //Presale phase modifiers
    modifier onlyWhileCreated() {if(currentPhase != Phase.Created) throw; _;}
    modifier onlyWhileRunning() {if(currentPhase != Phase.Running) throw; _;}
    modifier onlyWhileFinished() {if(currentPhase != Phase.Finished) throw; _;}
    modifier onlyWhileFinalized() {if(currentPhase != Phase.Finalized) throw; _;}
    modifier onlyWhileMigrating() {if(currentPhase != Phase.Migrating) throw; _;}

    

    event LogBuy(address indexed owner, uint value);
    event LogBurn(address indexed owner, uint value);
    event LogPhaseSwitch(Phase newPhase);
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);


    
    //if it is fallback, it shouldn't have enough gas?
    function() payable {
        buyTokens(msg.sender);
    }

    function buyTokens(address _buyer) public payable
        onlyWhileRunning
    {
        if(msg.value == 0) throw;
        uint newTokens = msg.value * priceTicker.getCentsPerETH() * 10**decimals / (priceUSD * 100);
        if (supply + newTokens > maxSupply) {
            var remainder = maxSupply - supply;
            balance[_buyer] += remainder;
            supply += remainder;
            lastBuyer = _buyer;
            refundValue = newTokens - remainder;
            LogBuy(_buyer, remainder);
        }
        else {
            balance[_buyer] += newTokens;
            supply += newTokens;
            LogBuy(_buyer, newTokens);
        }
        
        if (supply == maxSupply) {
            lastCentsPerETH = priceTicker.getCentsPerETH();
            priceTicker.initiateCleanUp();
            currentPhase = Phase.Finished;
            LogPhaseSwitch(Phase.Finished);
        }
    }

    function burnTokens(address _owner) public
        onlyCrowdsaleManager
        onlyWhileMigrating
    {
        uint tokens = balance[_owner];
        if(tokens == 0) throw;
        balance[_owner] = 0;
        supply -= tokens;
        LogBurn(_owner, tokens);

        // Automatically switch phase when migration is done.
        if(supply == 0) {
            currentPhase = Phase.Migrated;
            LogPhaseSwitch(Phase.Migrated);
        }
    }


    function balanceOf(address _owner) constant returns (uint256 balanceOf) {
        return balance[_owner];
    }
    
    function totalSupply() constant returns (uint256 totalSupply) {
        return supply;
    }
    
    function allowance(address _owner, address _spender) constant returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }

    function transfer(address _to, uint256 _value) onlyWhileRunning returns (bool success) 
    {
        if (balance[msg.sender] >= _value && _value > 0) {
            balance[msg.sender] -= _value;
            balance[_to] += _value;
            Transfer(msg.sender,_to,_value);
            return true;
        }
        return false;
    }
    
    function approve(address _spender, uint256 _value) onlyWhileRunning returns (bool success) {
        if (balance[msg.sender] >= _value && _value > 0) {
            allowed[msg.sender][_spender] = _value;
            Approval(msg.sender,_spender,_value);
            return true;
        }
        return false;
    }
    
    
    function transferFrom(address _from, address _to, uint256 _value) onlyWhileRunning returns (bool success) {
        
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

    function startPresale() public
        onlyTokenManager
        onlyWhileCreated
    {
        currentPhase = Phase.Running;
        LogPhaseSwitch(Phase.Running);
    }
    
    function finishPresale() public
        onlyTokenManager
        onlyWhileRunning
    {
        lastCentsPerETH = priceTicker.getCentsPerETH();
        priceTicker.initiateCleanUp();
        currentPhase = Phase.Finished;
        LogPhaseSwitch(Phase.Finished);
    }

    
    function finalizePresale() public
        onlyTokenManager
        onlyWhileFinished
    {
        if(!lastBuyer.send((refundValue * priceUSD * 100) / (lastCentsPerETH * 10**decimals))) throw;
        withdrawEther();
        currentPhase = Phase.Finalized;
        LogPhaseSwitch(Phase.Finalized);
    }

    function startMigration() public
        onlyTokenManager
        onlyWhileFinalized
    {
        if (crowdsaleManager == 0x0) throw;
        currentPhase = Phase.Migrating;
        LogPhaseSwitch(Phase.Migrating);
    }

    function withdrawEther() private
    {
        if(this.balance > 0) {
            if(!tokenManager.send(this.balance)) throw;
        }
    }

    function setCrowdsaleManager(address _mgr) public
        onlyTokenManager
        onlyWhileFinalized
    {
        crowdsaleManager = _mgr;
    }
}