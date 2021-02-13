resource "lxd_profile" "kubenode" {
  name = "kubenode"

  config = {
    "limits.cpu" = 2
    "security.privileged"  = true
    "security.nesting"     = true
    "linux.kernel_modules" = "ip_tables,ip6_tables,nf_nat,overlay,br_netfilter"
    "raw.lxc"       = <<-EOT
      lxc.apparmor.profile=unconfined
      lxc.cap.drop=
      lxc.cgroup.devices.allow=a
      lxc.mount.auto=proc:rw sys:rw
    EOT
    "user.user-data"       = <<-EOT
      #cloud-config
      ssh_authorized_keys:
        - ${file("~/.ssh/id_rsa.pub")}
      disable_root: false
      runcmd:
        - apt-get install -y linux-generic
        - curl -sfL https://get.k3s.io | sh -
    EOT
  }

  device {
    name = "eth0"
    type = "nic"

    properties = {
      network = "lxdbr0"
    }
  }

  device {
    type = "disk"
    name = "root"

    properties = {
      pool = "default"
      path = "/"
    }
  }
}

resource "lxd_container" "k8s" {
  count     = 1
  name      = "k8s${count.index}"
  image     = "ubuntu:18.04"
  ephemeral = false

  profiles = [lxd_profile.kubenode.name]
}

resource "time_sleep" "wait_cloud_init" {
  depends_on = [lxd_container.k8s]

  create_duration = "240s"
}

resource "rke_cluster" "cluster" {
  dynamic "nodes" {
    for_each = lxd_container.k8s

    content {
      address = nodes.value.ip_address
      user    = "root"
      role = [
        "controlplane",
        "etcd",
        "worker"
      ]
      ssh_key = file("~/.ssh/id_rsa")
    }
  }

  ingress {
    provider = "none"
  }

  ignore_docker_version = true

  depends_on = [time_sleep.wait_cloud_init]
}

resource "local_file" "kube_config_yaml" {
  filename = "${path.root}/kube_config.yaml"
  content  = rke_cluster.cluster.kube_config_yaml
}