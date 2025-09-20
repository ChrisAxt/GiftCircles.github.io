import React from 'react';
import { fireEvent } from '@testing-library/react-native';
import { render } from '../../test-utils';
import ListCard from '../ListCard';

describe('ListCard', () => {
  it('renders and calls onPress', () => {
    const onPress = jest.fn();
    const { getByText } = render(
      <ListCard
        name="Bob’s List"
        recipients={['Alice', 'Charlie']}
        itemCount={5}
        claimedCount={2}
        onPress={onPress}
      />
    );

    expect(getByText("Bob’s List")).toBeTruthy();
    expect(getByText(/Alice, Charlie/i)).toBeTruthy();
    // Component shows "2/5 claimed" as a single Text
    expect(getByText('2/5 claimed')).toBeTruthy();

    fireEvent.press(getByText("Bob’s List"));
    expect(onPress).toHaveBeenCalled();
  });
});
