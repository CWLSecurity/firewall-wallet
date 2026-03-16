// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

error TrustedVaultRegistry_Unauthorized();
error TrustedVaultRegistry_ZeroAddress();

contract TrustedVaultRegistry {
    address public owner;
    mapping(address => bool) public isRegistrar;
    mapping(address => bool) public isRecognizedVault;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RegistrarSet(address indexed registrar, bool indexed active);
    event RecognizedVaultSet(address indexed vault, bool indexed recognized);

    constructor(address owner_) {
        if (owner_ == address(0)) revert TrustedVaultRegistry_ZeroAddress();
        owner = owner_;
        isRegistrar[owner_] = true;
        emit OwnershipTransferred(address(0), owner_);
        emit RegistrarSet(owner_, true);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert TrustedVaultRegistry_Unauthorized();
        _;
    }

    modifier onlyRegistrar() {
        if (!isRegistrar[msg.sender]) revert TrustedVaultRegistry_Unauthorized();
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert TrustedVaultRegistry_ZeroAddress();
        address oldOwner = owner;
        owner = newOwner;
        isRegistrar[newOwner] = true;
        emit OwnershipTransferred(oldOwner, newOwner);
        emit RegistrarSet(newOwner, true);
    }

    function setRegistrar(address registrar, bool active) external onlyOwner {
        if (registrar == address(0)) revert TrustedVaultRegistry_ZeroAddress();
        isRegistrar[registrar] = active;
        emit RegistrarSet(registrar, active);
    }

    function setRecognizedVault(address vault, bool recognized) external onlyRegistrar {
        if (vault == address(0)) revert TrustedVaultRegistry_ZeroAddress();
        isRecognizedVault[vault] = recognized;
        emit RecognizedVaultSet(vault, recognized);
    }
}
