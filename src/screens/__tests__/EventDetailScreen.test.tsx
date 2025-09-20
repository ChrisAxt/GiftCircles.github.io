import React from 'react';
import { render } from '../../test-utils';
import { waitFor } from '@testing-library/react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import EventDetailScreen from '../EventDetailScreen';

jest.mock('../../lib/supabase');

describe('EventDetailScreen', () => {
  it('renders event stats and lists', async () => {
    const navigation = { setOptions: jest.fn(), navigate: jest.fn(), goBack: jest.fn() };
    const route = { params: { id: 'e1' } };

    const { getAllByText } = render(
      <SafeAreaProvider>
        <EventDetailScreen navigation={navigation} route={route} />
      </SafeAreaProvider>
    );

    await waitFor(() => expect(navigation.setOptions).toHaveBeenCalled());
    expect(getAllByText(/Members/i).length).toBeGreaterThan(0);
  });
});