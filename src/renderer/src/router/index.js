import { createRouter, createWebHashHistory } from "vue-router";

// 定义路由
const routes = [
  {
    path: "/",
    name: "Home",
    component: () => import("../views/home/index.vue"),
  },
  {
    path: "/settings",
    name: "Settings",
    component: () => import("../views/settings/index.vue"),
  },
  {
    path: '/tray',
    name: 'TrayWindow',
    component: () => import('../views/TrayWindow.vue')
  },
  {
    path: '/github-stars',
    name: 'GithubStars',
    component: () => import('../views/GithubStarView.vue')
  }
];

// 创建路由实例
const router = createRouter({
  history: createWebHashHistory(),
  routes
});

// 全局导航守卫
router.beforeEach((to, from, next) => {
  // 可在此添加导航守卫逻辑，如权限检查等
  next();
});

export default router;
