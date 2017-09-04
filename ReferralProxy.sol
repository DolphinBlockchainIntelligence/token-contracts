pragma solidity ^0.4.13;

interface IReferralProxyHandler {
    function buyThroughProxy(address _buyer) payable;
}

contract ReferralProxy {
    
    IReferralProxyHandler public presaleContract;
    
    function ReferralProxy(address _presaleContract) {
        presaleContract = IReferralProxyHandler(_presaleContract);
    }
    
    function () payable {
        presaleContract.buyThroughProxy.value(msg.value)(msg.sender);
    }
    
    function buyTokens(address _buyer) payable {
        presaleContract.buyThroughProxy.value(msg.value)(_buyer);
    }
    
}