const fs = require('fs');

const os = require('os')
const path = require('path')
const { dbService } = require('./db.service')
type Project = {
  ide: string
  projectName: string
  projectPath: string
  debHavenProject: any
}
const memoryData: Project[] = []

/**
 * 获取打开的项目
 * @returns Promise<Project[]> 打开的项目列表
 */
async function getOpenProjects(): Promise<Project[]> {
  try {
    // 查询%HOME/.debhaven/projects的文件列表
    const filePath = path.join(os.homedir(), '.devhaven/projects')

    // 检查目录是否存在
    if (!fs.existsSync(filePath)) {
      await fs.promises.mkdir(filePath, { recursive: true });
      return [];
    }

    // 使用异步读取文件列表
    const files = await fs.promises.readdir(filePath);

    // 处理文件并获取项目信息
    const projects: Project[] = [];

    for (const file of files) {
      try {
        // 检查文件名格式是否正确
        const parts = file.split('-');
        if (parts.length !== 2) continue;

        const [ide, base64Path] = parts;
        const projectPath = Buffer.from(base64Path, 'base64').toString('utf-8');

        // 获取项目信息
        const project = dbService.projects.getByPath(projectPath);
        if (!project) continue;

        projects.push({
          ide,
          projectName: project.name,
          projectPath,
          debHavenProject: project
        });

      } catch (fileError) {
        console.error(`处理文件 ${file} 时出错:`, fileError);
        // 继续处理下一个文件
        continue;
      }
    }

    // 更新内存缓存
    memoryData.splice(0, memoryData.length, ...projects);

    return projects;
  } catch (error) {
    console.error('获取打开的项目时出错:', error);
    return [];
  }
}

module.exports = {
  getOpenProjects
}
