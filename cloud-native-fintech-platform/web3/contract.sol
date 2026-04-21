// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract TransactionLogger {
    event TransactionLogged(string txHash);

    function log(string memory txHash) public {
        emit TransactionLogged(txHash);
    }
}
