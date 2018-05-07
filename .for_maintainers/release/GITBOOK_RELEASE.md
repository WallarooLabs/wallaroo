# Building and pushing Wallaroo Documentation Gitbook

This document is aimed at members of the Wallaroo team who might be building and pushing the Wallaroo Documentation Gitbook for a release candidate, release, or master branch. It serves as a checklist that can take your through the gitbook release process step-by-step.

To learn more about our release process, see [RELEASE.md].

## Prerequisites for building and pushing Wallaroo Documentation Gitbook

In order to build and push the Wallaroo Documentation Gitbook, you absolutely must have:

* The documentation repo token with access to the `wallaroolabs/docs.wallaroolabs.com` Github repository
* Vagrant installed

## Building and pushing Wallaroo Documentation Gitbook

Please note that this document was written with the assumption that you are using a clone of the `wallaroolabs/wallaroo` repo. This process will not work without modification if you try to use a fork rather than a clone of the repo. The `github-release.sh` script assumes you are using the `release` branch, `master` branch, or a release candidate branch that follows the `release-*` format.

### Start up the Wallaroo Vagrant box

From the top level `wallaroo` directory run the following:

```bash
cd  .release
vagrant up
```

This command will bring up a vagrant box with Wallaroo's build and release dependencies installed and with the `wallaroo` repo cloned to `/users/ubuntu/wallaroo`.

### SSH into Wallaroo Vagrant box

From within the `.release` directory run:

```bash
vagrant ssh
```

This will `ssh` you into the running Wallaroo box.

### Pull latest changes for your branch

From within the Wallaroo Vagrant box, you'll want to run a `git pull` for the branch you plan to use to build and release the Wallaroo Documentation Gitbook like so:

```bash
cd ~/wallaroo
git checkout origin/RELEASE_BRANCH
git pull
```

So if you were going to release the Wallaroo Documentation Gitbook using `release-0.4.0`, you'd run the following:

```bash
cd ~/wallaroo
git checkout origin/release-0.4.0
git pull
```

### Building and pushing the Wallaroo Documentation Gitbook

From within the Wallaroo Vagrant box run the following:

```bash
cd /users/ubuntu/wallaroo
bash .release/gitbook-release.sh DOCUMENTATION_REPO_TOKEN
```

So, for example, if your documentation repo token is `0xa0ece74981af`, you'd run:

```bash
bash .release/gitbook-release.sh 0xa0ece74981af
```

This will then build and push the Wallaroo Documentation Gitbook to the `wallaroolabs/docs.wallaroolabs.com` Github repository.


### Stop the Wallaroo Vagrant Box

Once you've successfully built and pushed the Wallaroo Documentation Gitbook, you can stop the Wallaroo Vagrant box with the following command from within the `.release` directory on your local machine:

```bash
vagrant halt
```
