# Setting Up Your Environment for Wallaroo in Vagrant

To get you up and running quickly with Wallaroo, we have provided a Vagrantfile which includes Wallaroo and related tools needed to run and modify a few example applications. We should warn that this Vagrantfile was created with the intent of getting users started quickly with Wallaroo and is not intended to be suitable for production. Wallaroo in Vagrant runs on Ubuntu Linux Xenial.

## Set up Environment for the Wallaroo Tutorial

### Linux Ubuntu and MacOS

If you haven't already done so, create a directory called `~/wallaroo-tutorial` and navigate there by running:

```bash
cd ~/
mkdir ~/wallaroo-tutorial
cd ~/wallaroo-tutorial
```

This will be our base directory in what follows. Create a directory for the current Wallaroo version and download the Wallaroo Vagrantfile:

```bash
mkdir wallaroo-0.5.4
cd wallaroo-0.5.4
mkdir vagrant
cd vagrant
curl -o Vagrantfile -J -L \
  https://raw.githubusercontent.com/WallarooLabs/wallaroo/0.5.4/vagrant/Vagrantfile
```

### Windows via Powershell

**Note:** This section of the guide assumes you are using Powershell.

If you haven't already done so, create a directory called `~/wallaroo-tutorial` and navigate there by running:

```bash
cd ~/
mkdir ~/wallaroo-tutorial
cd ~/wallaroo-tutorial
```

This will be our base directory in what follows. Create a directory for the current Wallaroo version and download the Wallaroo Vagrantfile:

```bash
mkdir wallaroo-0.5.4
cd wallaroo-0.5.4
mkdir vagrant
cd vagrant
Invoke-WebRequest -OutFile Vagrantfile `
  https://raw.githubusercontent.com/WallarooLabs/wallaroo/0.5.4/vagrant/Vagrantfile
```

## Installing VirtualBox

The Wallaroo Vagrant environment is dependent on the default provider,[VirtualBox](https://www.vagrantup.com/docs/virtualbox/). To install VirtualBox, download a installer or package for your OS [here](https://www.virtualbox.org/wiki/Downloads). Linux users can also use `apt-get` as documented below.

### Linux

```bash
sudo apt-get install virtualbox
```

## Installing Vagrant

### Linux Ubuntu, MacOS, and Windows

Download links for the appropriate installer or package for each supported OS can be found on the [Vagrant downloads page](https://www.vagrantup.com/downloads.html).

## Provision the Vagrant Box

Provisioning should take about 10 to 15 minutes. When it finishes, you will have a complete Wallaroo development environment. You won’t have to go through the provisioning process again unless you destroy the Wallaroo environment by running `vagrant destroy`.

To provision, run the following commands:

```bash
cd ~/wallaroo-tutorial/wallaroo-0.5.4/vagrant
vagrant up
```

## What's Included in the Wallaroo Vagrant Box

* **Go Compiler**: for compiling Wallaroo Go applications.

* **Giles Sender**: supplies data to Wallaroo applications over TCP.

* **Cluster Shutdown tool**: notifies the cluster to shut down cleanly.

* **Metrics UI**: receives and displays metrics for running Wallaroo applications.

* **Wallaroo Source Code**: full Wallaroo source code is provided, including Go example applications.

## Shutdown the Vagrant Box

You can shut down the Vagrant Box by running the following on your host machine:

```bash
cd ~/wallaroo-tutorial/wallaroo-0.5.4/vagrant
vagrant halt
```

## Restart the Vagrant Box

If you need to restart the Vagrant Box you can run the following command from the same directory:

```bash
vagrant up
```

## Conclusion

Awesome! All set. Time to try running your first Wallaroo application in Vagrant.
