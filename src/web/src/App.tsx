import {
  ApartmentOutlined,
  DashboardOutlined,
  DesktopOutlined,
  LogoutOutlined,
  UnorderedListOutlined,
  UserOutlined,
} from '@ant-design/icons';
import { Avatar, Button, Layout, Menu, Tooltip } from 'antd';
import { Link, Navigate, Route, Routes, useLocation } from 'react-router-dom';
import { clearToken, getToken } from './api';
import { AgentsPage } from './pages/AgentsPage';
import { DashboardPage } from './pages/DashboardPage';
import { LoginPage } from './pages/LoginPage';
import { RunnersPage } from './pages/RunnersPage';
import { TaskDetailPage } from './pages/TaskDetailPage';
import { TasksPage } from './pages/TasksPage';

function Shell({ children }: { children: React.ReactNode }) {
  const loc = useLocation();
  const selected = '/' + (loc.pathname.split('/')[1] || 'tasks');
  return (
    <Layout style={{ minHeight: '100vh' }}>
      <Layout.Sider
        theme="light"
        width={232}
        breakpoint="lg"
        collapsedWidth="0"
        style={{ borderRight: '1px solid #eceef1' }}
      >
        <div
          style={{
            position: 'sticky',
            top: 0,
            height: '100vh',
            display: 'flex',
            flexDirection: 'column',
          }}
        >
          <div className="orbit-brand">
            <span>🛰</span>
            <span>Orbit</span>
          </div>
          <Menu
            mode="inline"
            style={{ borderInlineEnd: 'none', flex: 1 }}
            selectedKeys={[selected]}
            items={[
              { key: '/tasks', icon: <UnorderedListOutlined />, label: <Link to="/tasks">Tasks</Link> },
              { key: '/agents', icon: <ApartmentOutlined />, label: <Link to="/agents">Agents</Link> },
              { key: '/runners', icon: <DesktopOutlined />, label: <Link to="/runners">Runners</Link> },
              {
                key: '/dashboard',
                icon: <DashboardOutlined />,
                label: <Link to="/dashboard">Dashboard</Link>,
              },
            ]}
          />
          <div className="orbit-sider-footer">
            <div className="orbit-user">
              <Avatar size={28} icon={<UserOutlined />} style={{ background: '#3370ff' }} />
              <span style={{ flex: 1, color: '#646a73', fontSize: 13 }}>Account</span>
              <Tooltip title="Logout">
                <Button
                  type="text"
                  size="small"
                  icon={<LogoutOutlined />}
                  onClick={() => {
                    clearToken();
                    location.href = '/login';
                  }}
                />
              </Tooltip>
            </div>
          </div>
        </div>
      </Layout.Sider>
      <Layout>
        <Layout.Content style={{ padding: '24px 32px' }}>{children}</Layout.Content>
      </Layout>
    </Layout>
  );
}

export function App() {
  const authed = !!getToken();
  return (
    <Routes>
      <Route path="/login" element={authed ? <Navigate to="/tasks" /> : <LoginPage />} />
      {!authed ? (
        <Route path="*" element={<Navigate to="/login" replace />} />
      ) : (
        <>
          <Route path="/" element={<Navigate to="/tasks" replace />} />
          <Route path="/tasks" element={<Shell><TasksPage /></Shell>} />
          <Route path="/tasks/:id" element={<Shell><TaskDetailPage /></Shell>} />
          <Route path="/agents" element={<Shell><AgentsPage /></Shell>} />
          <Route path="/runners" element={<Shell><RunnersPage /></Shell>} />
          <Route path="/dashboard" element={<Shell><DashboardPage /></Shell>} />
        </>
      )}
    </Routes>
  );
}
