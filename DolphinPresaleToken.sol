pragma solidity ^0.4.13;
import "github.com/oraclize/ethereum-api/oraclizeAPI.sol";


library SafeMath {
  function mul(uint256 a, uint256 b) internal returns (uint256) {
    uint256 c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function div(uint256 a, uint256 b) internal returns (uint256) {
    uint256 c = a / b;
    return c;
  }

  function sub(uint256 a, uint256 b) internal returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  function add(uint256 a, uint256 b) internal returns (uint256) {
    uint256 c = a + b;
    assert(c >= a);
    return c;
  }

}

contract Ownable {
  address public owner;

  function Ownable() {
    owner = msg.sender;
  }

  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  function transferOwnership(address newOwner) onlyOwner {
    if (newOwner != address(0)) {
      owner = newOwner;
    }
  }

}

contract Freezable is Ownable {
    
    bool frozen = false;
    
    modifier whileNotFrozen {assert(frozen != true); _;}
    
    function freeze() onlyOwner {
        frozen = true;
    }
    
    function unfreeze() onlyOwner {
        frozen = false;
    }
    
}

contract CMCEthereumTicker is usingOraclize, Ownable {
    using SafeMath for uint;
    
    uint256 centsPerETH;
    uint256 delay;
    bool enabled;
    
    address manager;
    
    modifier onlyOwnerOrManager() { require(msg.sender == owner || msg.sender == manager); _; }
    
    event newOraclizeQuery(string description);
    event newPriceTicker(string price);
    
    
    function CMCEthereumTicker(address _manager, uint256 _delay) {
        oraclize_setProof(proofType_NONE);
        enabled = false;
        manager = _manager;
        delay = _delay;
    }
    
    function getCentsPerETH() constant returns(uint256) {
        return centsPerETH;
    }
    
    function getEnabled() constant returns(bool) {
        return enabled;
    }
    
    function enable() 
        onlyOwnerOrManager
    {
        require(enabled == false);
        enabled = true;
        update_instant();
    }
    
    function disable() 
        onlyOwnerOrManager
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
            oraclize_query(delay, "URL", "json(https://api.coinmarketcap.com/v1/ticker/ethereum/?convert=USD).0.price_usd");
        }
    }
    
    function payToManager(uint256 _amount) 
        onlyOwnerOrManager
    {
        manager.transfer(_amount);
    }
    
    function () payable {}
    
}

contract TickerController is Ownable{
    
    //Ticker contract
    CMCEthereumTicker priceTicker;
    
    function createTicker(uint256 _delay) 
        onlyOwner
    {
        priceTicker = new CMCEthereumTicker(owner, _delay);
    }
    
    function attachTicker(address _tickerAddress)
        onlyOwner
    {
         priceTicker = CMCEthereumTicker(_tickerAddress);   
    }
    
    function enableTicker() 
        onlyOwner
    {
        priceTicker.enable();
    }
    
    function disableTicker() 
        onlyOwner
    {
        priceTicker.disable();
    }
    
    function sendToTicker() payable
        onlyOwner
    {
        assert(address(priceTicker) != 0x0);
        address(priceTicker).transfer(msg.value);
    }
    
    function withdrawFromTicker(uint _amount)
        onlyOwner
    {
        assert(address(priceTicker) != 0x0);
        priceTicker.payToManager(_amount);
    }
    
    function tickerAddress() constant returns (address) {
        return address(priceTicker);
    }
    
    function getCentsPerETH() constant returns (uint256) {
        return priceTicker.getCentsPerETH();
    }
}

contract DBIPToken is Freezable {
    using SafeMath for uint256;
    
    //ERC20 Fields
    
    uint supply;
    
    //ERC20 Containers
    mapping (address => uint256) private balance;
    mapping (address => mapping(address => uint256)) private allowed;
    
    //ERC 20 Additional info
    string public constant name = "Dolphin Presale Token";
    string public constant symbol = "DBIP";
    uint256 public constant decimals = 18;
    
    //ERC20 events
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);

    
    //Modifier to defend against shortened address attack
     
    modifier minimalPayloadSize(uint256 size) {
        assert(msg.data.length >= size + 4);
        _;
    }
    
    function DBIPToken (uint256 _initial_supply) {
        balance[owner] = _initial_supply;
        supply = _initial_supply;
    }
    
    //Method to generate additional tokens. Can only be called by parent contract.
    
    function raiseSupply (uint256 _new_supply) 
        onlyOwner
    {
        uint256 increase = _new_supply.sub(supply);
        balance[owner] = balance[owner].add(increase);
        supply = supply.add(increase);
    }
    
    // Method that allows parent to transfer during freeze
    
    function ownerTransfer(address _to, uint256 _value) onlyOwner returns (bool success) 
    {
        assert(_value > 0);
        
        balance[owner] = balance[owner].sub(_value);
        balance[_to] = balance[_to].add(_value);
        Transfer(owner,_to,_value);
        
        return true;
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

    function transfer(address _to, uint256 _value) whileNotFrozen minimalPayloadSize(2 * 32) returns (bool success) 
    {
        assert(_value > 0);
        
        balance[msg.sender] = balance[msg.sender].sub(_value);
        balance[_to] = balance[_to].add(_value);
        Transfer(msg.sender,_to,_value);
        
        return true;
    }
    
    function approve(address _spender, uint256 _value) whileNotFrozen  returns (bool success) {
        assert((_value == 0) || (allowed[msg.sender][_spender] == 0));
        
        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender,_spender,_value);
        
        return true;
    }
    
    
    function transferFrom(address _from, address _to, uint256 _value) whileNotFrozen minimalPayloadSize(3 * 32) returns (bool success) {
        
        assert(_value > 0);

        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
        balance[_from] = balance[_from].sub(_value);
        balance[_to] = balance[_to].add(_value);
        Transfer(_from,_to,_value);
        
        return true;

    }
    
}

contract ReferralProxyHandler is Ownable{
    
    // Proxy is a contract throught which referral investors buy tokens
    address public proxy;
    // amount of tokens sold through proxy
    uint256 public fundedProxy = 0;
    
    modifier onlyProxy { require(msg.sender == proxy); _; }
    
    function setProxy(address _proxy) 
        onlyOwner
    {
        proxy = _proxy;
    }
    
    function buyThroughProxy(address _buyer) payable;
    
}

contract PresaleToken is TickerController, ReferralProxyHandler {
    using SafeMath for uint256;

    function PresaleToken(uint256 _limitUSD, uint256 _priceCents) {
        priceCents = _priceCents;
        maxSupply = (uint256(10)**decimals).mul(100).mul(_limitUSD).div(_priceCents);
        token = new DBIPToken(maxSupply);
        assert(decimals == token.decimals());
    }
    
    enum Phase {
        Created,
        Running,
        Finished,
        Finalized,
        Migrating,
        Migrated
    }
    
    // Token
    DBIPToken public token;
    // maximum token supply
    uint256 public maxSupply;
    // price of 1 token in USD cents
    uint256 public priceCents;
    // Decimals of token needed for most operations
    uint256 public decimals = 18;
    
    //Phase on contract creation
    Phase public currentPhase = Phase.Created;

    // amount of tokens already sold
    uint256 public funded = 0;
    // amount of tokens given via giveTokens
    uint256 public given = 0;


    // Migration manager has privileges to burn tokens during migration.
    address public migrationManager;
    
    // The last buyer is the buyer that purchased
    // tokens that add up to the maxSupply or more.
    // During the presale finalization they are refunded
    // the excess USD according to lastCentsPerETH.
    address lastBuyer;
    uint256 refundValue = 0;
    uint256 lastCentsPerETH = 0;
    
    // Whether the funding cap was already raised
    bool capRaised = false;

    //External access modifier
    modifier onlyMigrationManager() { require(msg.sender == migrationManager); _; }
    
    //Presale phase modifiers
    modifier onlyWhileCreated() {assert(currentPhase == Phase.Created); _;}
    modifier onlyWhileRunning() {assert(currentPhase == Phase.Running); _;}
    modifier onlyWhileFinished() {assert(currentPhase == Phase.Finished); _;}
    modifier onlyWhileFinalized() {assert(currentPhase == Phase.Finalized); _;}
    modifier onlyBeforeMigration() {assert(currentPhase != Phase.Migrating && currentPhase != Phase.Migrated); _;}
    modifier onlyWhileMigrating() {assert(currentPhase == Phase.Migrating); _;}
    
    //Presale events
    event LogBuy(address indexed owner, uint256 value, uint256 centsPerETH);
    event LogGive(address indexed owner, uint256 value, string reason);
    event LogMigrate(address indexed owner, uint256 value);
    event LogPhaseSwitch(Phase newPhase);
    
    ///Presale-specific functions
    
    function() payable {
        buyTokens(msg.sender);
    }

    function buyTokens(address _buyer) payable
        onlyWhileRunning
    {
        require(msg.value != 0);
        require(priceTicker.getEnabled());
        
        uint256 centsPerETH = getCentsPerETH();
        require(centsPerETH != 0);
        
        uint256 newTokens = msg.value.mul(centsPerETH).mul(uint256(10)**decimals).div(priceCents.mul(1 ether / 1 wei));
        assert(newTokens != 0);
        
        if (funded.add(newTokens) > maxSupply) {
            uint256 remainder = maxSupply.sub(funded);
            token.ownerTransfer(_buyer, remainder);
            funded = funded.add(remainder);
            lastBuyer = _buyer;
            refundValue = newTokens.sub(remainder);
            LogBuy(_buyer, remainder, centsPerETH);
        }
        else {
            token.ownerTransfer(_buyer, newTokens);
            funded = funded.add(newTokens);
            LogBuy(_buyer, newTokens, centsPerETH);
        }
        
        if (funded == maxSupply) {
            lastCentsPerETH = centsPerETH;
            currentPhase = Phase.Finished;
            LogPhaseSwitch(Phase.Finished);
        }
    }
    
    function buyThroughProxy(address _buyer) payable
        onlyProxy
        onlyWhileRunning
    {
        require(msg.value != 0);
        require(priceTicker.getEnabled());
        
        uint256 centsPerETH = getCentsPerETH();
        require(centsPerETH != 0);
        
        uint256 newTokens = msg.value.mul(centsPerETH).mul(uint256(10)**decimals).div(priceCents.mul(1 ether / 1 wei));
        assert(newTokens != 0);
        
        if (funded.add(newTokens) > maxSupply) {
            uint256 remainder = maxSupply.sub(funded);
            token.transfer(_buyer, remainder);
            funded = funded.add(remainder);
            fundedProxy = fundedProxy.add(remainder);
            lastBuyer = _buyer;
            refundValue = newTokens.sub(remainder);
            LogBuy(_buyer, remainder, centsPerETH);
        }
        else {
            token.transfer(_buyer, newTokens);
            funded = funded.add(newTokens);
            fundedProxy = fundedProxy.add(newTokens);
            LogBuy(_buyer, newTokens, centsPerETH);
        }
        
        if (funded == maxSupply) {
            lastCentsPerETH = centsPerETH;
            currentPhase = Phase.Finished;
            LogPhaseSwitch(Phase.Finished);
        }
    }

    function migrateTokens(address _owner)
        onlyMigrationManager
        onlyWhileMigrating
    {
        assert(token.balanceOf(_owner) != 0);
        var migratedValue = token.balanceOf(_owner);
        funded = funded.sub(migratedValue);
        LogMigrate(_owner, migratedValue);
        if(funded == 0) {
            currentPhase = Phase.Migrated;
            LogPhaseSwitch(Phase.Migrated);
        }
    }

    function startPresale()
        onlyOwner
        onlyWhileCreated
    {
        assert(address(priceTicker) != address(0));
        token.freeze();
        currentPhase = Phase.Running;
        LogPhaseSwitch(Phase.Running);
    }
    
    function finishPresale()
        onlyOwner
        onlyWhileRunning
    {
        lastCentsPerETH = priceTicker.getCentsPerETH();
        currentPhase = Phase.Finished;
        LogPhaseSwitch(Phase.Finished);
    }

    
    function finalizePresale()
        onlyOwner
        onlyWhileFinished
    {   
        if (refundValue != 0) {
            lastBuyer.transfer((refundValue.mul(priceCents).mul(1 ether / 1 wei)).div(lastCentsPerETH.mul(uint256(10)**decimals)));
        }
        withdrawEther();
        token.unfreeze();
        currentPhase = Phase.Finalized;
        LogPhaseSwitch(Phase.Finalized);
    }

    function startMigration()
        onlyOwner
        onlyWhileFinalized
    {
        assert(migrationManager != address(0));
        token.freeze();
        currentPhase = Phase.Migrating;
        LogPhaseSwitch(Phase.Migrating);
    }

    function withdrawEther() private
    {
        assert(this.balance > 0);
        owner.transfer(this.balance);
    }

    function setMigrationManager(address _mgr)
        onlyOwner
        onlyWhileFinalized
    {
        migrationManager = _mgr;
    }
    
    function raiseCap(uint _newCap)
        onlyOwner
        onlyWhileFinished
    {
        assert(!capRaised);
        assert(_newCap > maxSupply);
        maxSupply = _newCap;
        token.raiseSupply(_newCap);
        if (refundValue != 0) {
           token.ownerTransfer(lastBuyer, refundValue);
           refundValue = 0;
        }
        currentPhase = Phase.Running;
        LogPhaseSwitch(Phase.Running);
    }
    
    function giveTokens(address _address, uint _value, string _reason) 
        onlyOwner
        onlyBeforeMigration
        
    {
        token.ownerTransfer(_address, _value);
        funded = funded.add(_value);
        given = given.add(_value);
        LogGive(_address, _value, _reason);
    }
    
}