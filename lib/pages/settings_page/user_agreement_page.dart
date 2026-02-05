import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../utils/theme_manager.dart';

class UserAgreementPage extends StatelessWidget {
  const UserAgreementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isCupertino = ThemeManager().isCupertinoFramework;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (isCupertino) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(
          middle: Text('用户协议'),
        ),
        backgroundColor: isDark ? CupertinoColors.black : CupertinoColors.systemGroupedBackground,
        child: SafeArea(
          child: _buildContent(context, true),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('用户协议'),
      ),
      body: _buildContent(context, false),
    );
  }

  Widget _buildContent(BuildContext context, bool isCupertino) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('CyreneMusic 使用协议'),
          _buildSectionBody('词语约定：\n“本项目”指 CyreneMusic 应用及其相关开源代码；\n“使用者”指下载、安装、运行或以任何方式使用本项目的个人或组织；\n“音源”指由使用者自行导入或配置的第三方音频数据来源（包括但不限于 API、链接、本地文件路径等）；\n“版权数据”指包括但不限于音频、专辑封面、歌曲名、艺术家信息等受知识产权保护的内容。'),
          
          _buildSectionTitle('一、数据来源与播放机制'),
          _buildSectionBody('1.1 本项目 本身不具备获取音频流的能力。所有音频播放均依赖于使用者自行导入或配置的“音源”。本项目仅将用户输入的歌曲信息（如标题、艺术家等）传递给所选音源，并播放其返回的音频链接。'),
          _buildSectionBody('1.2 本项目 不对音源返回内容的合法性、准确性、完整性或可用性作任何保证。若音源返回错误、无关、失效或侵权内容，由此产生的任何问题均由使用者及音源提供方承担，本项目开发者不承担任何责任。'),
          _buildSectionBody('1.3 使用者应自行确保所导入音源的合法性，并对其使用行为负全部法律责任。'),
          
          _buildSectionTitle('二、账号与数据同步'),
          _buildSectionBody('2.1 本平台提供的账号系统 仅用于云端保存歌单、播放历史等用户偏好数据，不用于身份认证、商业推广、数据分析或其他用途。'),
          _buildSectionBody('2.2 所有同步至云端的数据均由使用者主动上传，本项目不对这些数据的内容、合法性或安全性负责。'),
          
          _buildSectionTitle('三、版权与知识产权'),
          _buildSectionBody('3.1 本项目 不存储、不分发、不缓存任何音频文件或版权数据。所有版权数据均由使用者通过外部音源实时获取。'),
          _buildSectionBody('3.2 使用者在使用本项目过程中接触到的任何版权内容（如歌曲、专辑图等），其权利归属于原著作权人。使用者应遵守所在国家/地区的版权法律法规。'),
          _buildSectionBody('3.3 强烈建议使用者在24小时内清除本地缓存的版权数据（如有），以避免潜在侵权风险。本项目不主动缓存音频，但部分系统或浏览器可能自动缓存，使用者需自行管理。'),
          
          _buildSectionTitle('四、开源与许可'),
          _buildSectionBody('4.1 本项目为 完全开源软件，基于 Apache License 2.0 发布。使用者可自由使用、修改、分发本项目代码，但须遵守 Apache 2.0 许可证条款。'),
          _buildSectionBody('4.2 本项目中使用的第三方资源（如图标、字体等）均注明来源。若存在未授权使用情况，请联系开发者及时移除。'),
          
          _buildSectionTitle('五、免责声明'),
          _buildSectionBody('5.1 使用者理解并同意：因使用本项目或依赖外部音源所导致的任何直接或间接损失（包括但不限于数据丢失、设备损坏、法律纠纷、隐私泄露等），均由使用者自行承担。'),
          _buildSectionBody('5.2 本项目开发者 不对本项目的功能完整性、稳定性、安全性或适配性作任何明示或暗示的担保。'),
          
          _buildSectionTitle('六、使用限制'),
          _buildSectionBody('6.1 本项目 仅用于技术学习、个人非商业用途。禁止将本项目用于任何违反当地法律法规的行为（如盗版传播、侵犯版权、非法爬取等）。'),
          _buildSectionBody('6.2 若使用者所在司法管辖区禁止使用此类工具，使用者应立即停止使用。因违规使用所引发的一切后果，由使用者自行承担。'),
          
          _buildSectionTitle('七、尊重版权'),
          _buildSectionBody('7.1 音乐创作不易，请尊重艺术家与版权方的劳动成果。支持正版音乐，优先使用合法授权的音源服务。'),
          
          _buildSectionTitle('八、协议接受'),
          _buildSectionBody('8.1 一旦您下载、安装、运行或以任何方式使用 CyreneMusic，即视为您已阅读、理解并无条件接受本协议全部条款。'),
          _buildSectionBody('8.2 本协议可能随项目更新而修订，修订后将发布于项目仓库。继续使用即视为接受最新版本。'),
          
          const SizedBox(height: 16),
          const Align(
            alignment: Alignment.centerRight,
            child: Text(
              '最新更新时间：2026年2月4日',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 12.0),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
    );
  }

  Widget _buildSectionBody(String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        body,
        style: const TextStyle(
          fontSize: 15,
          height: 1.6,
          color: Colors.grey,
        ),
      ),
    );
  }
}
